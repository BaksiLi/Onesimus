import annotation from './remark-annotation.mjs';
import 'markdown-it-inline-annotation/styles.css';

export default function extend({ remark, rehype }) {
  remark.use(annotation, { spaceAlignment: 'auto', inlineStyles: false });
}
