import MarkdownIt from 'markdown-it';
import texmath from 'markdown-it-texmath';
import footnote from 'markdown-it-footnote';
import tasks from 'markdown-it-task-lists';
import katex from 'katex';
import extend from 'webpreview:extensions';

const md = new MarkdownIt({ html: false, linkify: true });
md.use(texmath, { engine: katex, delimiters: ['dollars', 'brackets'], katexOptions: { trust: false, throwOnError: false } });
md.use(footnote).use(tasks);
extend(md);
// Keep the parser's source ranges on rendered blocks, including custom math/code.
const render = md.renderer.render.bind(md.renderer);
md.renderer.render = (tokens, options, env) => {
  let headings = new Map();
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.type === 'heading_open') {
      const label = tokens[i + 1].content.toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').trim().replace(/\s+/g, '-');
      const count = headings.get(label) || 0;
      headings.set(label, count + 1);
      token.attrSet('id', label + (count ? '-' + count : ''));
    }
  }
  return render(tokens, options, env);
};
for (const type of new Set([...Object.keys(md.renderer.rules), 'paragraph_open', 'heading_open', 'blockquote_open',
  'bullet_list_open', 'ordered_list_open', 'list_item_open', 'tr_open'])) {
  const original = md.renderer.rules[type] || ((tokens, i, options, env, renderer) => renderer.renderToken(tokens, i, options));
  md.renderer.rules[type] = (tokens, i, options, env, renderer) => {
    const token = tokens[i], html = original(tokens, i, options, env, renderer);
    return token.map && token.block && token.nesting >= 0
      ? html.replace(/^<(\w+)/, `<$1 data-line="${token.map[0] + 1}" data-end-line="${token.map[1]}"`) : html;
  };
}
const image = md.renderer.rules.image;
md.renderer.rules.image = (tokens, i, options, env, renderer) => {
  const token = tokens[i], source = token.attrGet('src');
  if (!/^(?:[a-z][\w+.-]*:|\/\/|\/)/i.test(source)) token.attrSet('src', './media/' + source);
  return image(tokens, i, options, env, renderer);
};
const link = md.renderer.rules.link_open || ((tokens, i, options, env, renderer) => renderer.renderToken(tokens, i, options));
md.renderer.rules.link_open = (tokens, i, options, env, renderer) => {
  const token = tokens[i], href = token.attrGet('href');
  if (/^(?:https?:|mailto:)/i.test(href)) {
    token.attrSet('target', '_blank'); token.attrSet('rel', 'noopener noreferrer');
  } else if (!/^(?:[a-z][\w+.-]*:|\/|#)/i.test(href)) {
    token.attrSet('data-file', href.split('#')[0]);
  }
  return link(tokens, i, options, env, renderer);
};
export function renderMarkdown(text) { return md.render(text); }
export function parseMarkdown(text) { return md.parse(text, {}); }
export const engine = 'markdown-it';
