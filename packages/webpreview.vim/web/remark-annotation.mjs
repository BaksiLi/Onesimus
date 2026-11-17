import { findInlineAnnotationModels, renderInlineAnnotationModelToHtml } from 'markdown-it-inline-annotation/core';
import { fromHtml } from 'hast-util-from-html';
import { replaceInline } from './remark-source.mjs';

export default function annotation(options = {}) {
  return (tree, file) => {
    const source = String(file);
    replaceInline(tree, source, (start, end) => findInlineAnnotationModels(source, start, end, options),
      (model, position) => ({ type: 'inlineAnnotation', value: model.base.raw, model, position,
        data: { hName: 'span', hProperties: { dataSource: model.source },
          hChildren: fromHtml(renderInlineAnnotationModelToHtml(model, options), { fragment: true }).children } }));
  };
}
