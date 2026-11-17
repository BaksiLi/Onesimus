import { decodeString } from 'micromark-util-decode-string';
import { location } from 'vfile-location';

// Replace source-backed inline fragments in MDAST; surrounding nodes keep their
// identity and positions. Code, links and math keep ownership of their content.
export function replaceInline(tree, source, matches, create) {
  const { toPoint } = location(source);
  const position = (start, end) => ({ start: toPoint(start), end: toPoint(end) });
  const text = (start, end) => ({ type: 'text', value: decodeString(source.slice(start, end)), position: position(start, end) });
  function walk(parent) {
    if (!parent.children || ['link', 'linkReference', 'image', 'imageReference', 'inlineCode', 'code',
      'inlineMath', 'math', 'html', 'inlineAnnotation'].includes(parent.type)) return;
    for (const child of parent.children) walk(child);
    if (!parent.position || !['paragraph', 'heading', 'tableCell', 'emphasis', 'strong', 'delete'].includes(parent.type)) return;
    const models = matches(parent.position.start.offset, parent.position.end.offset);
    for (const model of [...models].reverse()) {
      const first = parent.children.findIndex(child => child.position?.end.offset > model.start);
      const last = parent.children.findLastIndex(child => child.position?.start.offset < model.end);
      if (first < 0 || last < first) continue;
      const children = parent.children.slice(first, last + 1);
      if (children.some(child => child.type === 'inlineAnnotation' || (child.type !== 'text'
        && (child.position.start.offset < model.start || child.position.end.offset > model.end)))) continue;
      const before = children[0].position.start.offset, after = children.at(-1).position.end.offset;
      parent.children.splice(first, children.length,
        ...(before < model.start ? [text(before, model.start)] : []),
        create(model, position(model.start, model.end)),
        ...(after > model.end ? [text(model.end, after)] : []));
    }
  }
  walk(tree);
}

