import { unified } from 'unified';
import parse from 'remark-parse';
import gfm from 'remark-gfm';
import math from 'remark-math';
import { toHast } from 'mdast-util-to-hast';
import { toString } from 'mdast-util-to-string';
import { fromHtml } from 'hast-util-from-html';
import stringify from 'rehype-stringify';
import { visit } from 'unist-util-visit';
import katex from 'katex';
import { replaceInline } from './remark-source.mjs';
import extend from 'webpreview:extensions';

// Bracket math reads original source ranges; backslashes remain meaningful even
// after CommonMark has decoded character escapes in text nodes.
function brackets() {
  return (tree, file) => {
    const source = String(file);
    const matches = (start, end) => [...source.slice(start, end).matchAll(/\\\(([\s\S]*?)\\\)|\\\[([\s\S]*?)\\\]/g)]
      .filter(match => (source.slice(0, start + match.index).match(/\\*$/)[0].length % 2) === 0)
      .map(match => ({ start: start + match.index, end: start + match.index + match[0].length,
        value: match[1] ?? match[2], display: match[2] !== undefined }));
    replaceInline(tree, source, matches, (match, position) => ({ type: 'inlineMath',
      value: match.value, position, data: { displayMode: match.display } }));
  };
}
const remark = unified().use(parse).use(gfm).use(math).use(brackets);
const rehype = unified().use(stringify);
extend({ remark, rehype });

const literalHtml = (state, node) => ({ type: 'text', value: node.value, position: node.position });
function formula(state, node) {
  const html = katex.renderToString(node.value, { trust: false, throwOnError: false,
    displayMode: node.type === 'math' || node.data?.displayMode });
  const result = fromHtml(html, { fragment: true }).children[0];
  result.position = node.position;
  if (node.type === 'math') {
    result.properties['data-line'] = node.position.start.line;
    result.properties['data-end-line'] = node.position.end.line;
  }
  return result;
}
export function parseMarkdown(text) {
  return remark.runSync(remark.parse(text), { value: text });
}
export function renderMarkdown(text) {
  const tree = parseMarkdown(text);
  const headings = new Map();
  visit(tree, 'heading', node => {
    const label = toString(node).toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').trim().replace(/\s+/g, '-');
    const count = headings.get(label) || 0;
    headings.set(label, count + 1);
    node.data = { ...node.data, hProperties: { ...node.data?.hProperties, id: label + (count ? '-' + count : '') } };
  });
  const html = toHast(tree, { handlers: { html: literalHtml, math: formula, inlineMath: formula } });
  visit(html, 'element', node => {
    const props = node.properties;
    if (node.position && /^(p|h[1-6]|blockquote|[ou]l|li|tr|table|pre|aside|figure|section|div)$/.test(node.tagName)) {
      props['data-line'] = node.position.start.line;
      props['data-end-line'] = node.position.end.line - (node.position.end.column === 1 ? 1 : 0);
    }
    if (node.tagName === 'img' && props.src && !/^(?:[a-z][\w+.-]*:|\/\/|\/)/i.test(props.src)) props.src = './media/' + props.src;
    if (node.tagName === 'a' && props.href) {
      if (/^(?:https?:|mailto:)/i.test(props.href)) {
        props.target = '_blank'; props.rel = ['noopener', 'noreferrer'];
      } else if (/^(?:[a-z][\w+.-]*:|\/\/)/i.test(props.href)) {
        delete props.href;
      } else if (!/^(?:\/|#)/.test(props.href)) props['data-file'] = props.href.split('#')[0];
    }
  });
  return rehype.stringify(rehype.runSync(html, { value: text }));
}
export const engine = 'remark';
