import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { unified } from 'unified';
import parse from 'remark-parse';
import gfm from 'remark-gfm';
import math from 'remark-math';
import { visit } from 'unist-util-visit';
import annotation from '../web/remark-annotation.mjs';

const require = createRequire(import.meta.url);
const fixtures = name => JSON.parse(readFileSync(require.resolve('markdown-it-inline-annotation/fixtures/' + name), 'utf8')).cases;
for (const fixture of fixtures('models.json')) {
  const parser = unified().use(parse).use(gfm).use(math).use(annotation, fixture.options);
  const tree = parser.runSync(parser.parse(fixture.input), { value: fixture.input });
  const models = [];
  visit(tree, 'inlineAnnotation', node => {
    models.push(node.model);
    assert.equal(fixture.input.slice(node.position.start.offset, node.position.end.offset), node.model.source);
  });
  assert.deepEqual(models, fixture.models, fixture.id);
}
console.log('remark annotation: all 13 shared source-model fixtures PASS');
