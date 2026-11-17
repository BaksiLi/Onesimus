"""Map generated latexdiff lines to surviving manuscript text, without editing it."""
from collections import Counter, defaultdict
from difflib import SequenceMatcher
import re


def blank(text):
    return re.sub(r'[^\n]', ' ', text)


def uncomment(text):
    return re.sub(r'\\.|%[^\n]*', lambda m: blank(m[0]) if m[0].startswith('%') else m[0], text)


def surviving(text):
    """Remove latexdiff wrappers/deletions, keeping generated line numbers intact."""
    text = re.sub(r'%DIF PREAMBLE EXTENSION.*?%DIF END PREAMBLE[^\n]*',
                  lambda m: blank(m[0]), text, flags=re.S)
    text = uncomment(text)
    text = re.sub(r'\\DIFdelbegin(?:FL)?\b.*?\\DIFdelend(?:FL)?\b',
                  lambda m: blank(m[0]), text, flags=re.S)
    chars = list(text)
    for match in re.finditer(r'\\DIF(add|del)(?:FL)?\s*\{', text):
        depth, end = 1, None
        for token in re.finditer(r'\\.|[{}]', text[match.end():]):
            if token[0] == '{':
                depth += 1
            elif token[0] == '}':
                depth -= 1
            if not depth:
                end = match.end() + token.start()
                break
        if end is not None:
            if match[1] == 'del':
                chars[match.start():end + 1] = blank(text[match.start():end + 1])
            else:
                chars[match.start():match.end()] = blank(text[match.start():match.end()])
                chars[end] = ' '
    return re.sub(r'\\DIF(?:add|del)(?:begin|end)(?:FL)?\b', lambda m: blank(m[0]), ''.join(chars))


def tokens(text):
    body = text.find(r'\begin{document}')
    if body >= 0:
        text = blank(text[:body]) + text[body:]
    result, lines = [], []
    for line, text in enumerate(text.splitlines(), 1):
        words = re.findall(r'\\[a-zA-Z@]+|\w+|[^\s]', text)
        result.extend(words)
        lines.extend([line] * len(words))
    return result, lines


def unique(sequence, part):
    count = 0
    for i, item in enumerate(sequence):
        if item == part[0] and sequence[i:i + len(part)] == part:
            count += 1
            if count > 1:
                return False
    return count == 1


class SourceMap:
    def __init__(self, generated, files):
        rendered, lines = tokens(surviving(generated.read_text(encoding='utf-8')))
        votes = defaultdict(Counter)
        for source in files:
            if source.suffix not in ('.tex', '.ltx'):
                continue
            original, source_lines = tokens(uncomment(source.read_text(encoding='utf-8')))
            for block in SequenceMatcher(None, original, rendered).get_matching_blocks():
                part = original[block.a:block.a + block.size]
                # Short or repeated fragments cannot identify a manuscript passage.
                if block.size < 4 or not unique(original, part) or not unique(rendered, part):
                    continue
                for offset in range(block.size):
                    votes[lines[block.b + offset]][(str(source), source_lines[block.a + offset])] += 1
        self.lines = {}
        for line, candidates in votes.items():
            ranked = candidates.most_common(2)
            if len(ranked) == 1 or ranked[0][1] > ranked[1][1]:
                self.lines[line] = ranked[0][0]

    def locate(self, line):
        if not self.lines:
            raise ValueError('No unambiguous manuscript passage for this comparison.')
        nearest = min(self.lines, key=lambda candidate: (abs(candidate - line), candidate < line))
        file, source_line = self.lines[nearest]
        position = {'file': file, 'line': source_line, 'column': 1}
        if nearest != line:
            position['approximate'] = True
        return position
