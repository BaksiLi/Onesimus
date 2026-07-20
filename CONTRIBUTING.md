# Contributing

Onesimus is small enough that a pull request is the most useful place to
discuss a change. Say what problem it solves. A new plugin or abstraction is
not, by itself, a reason to make the system larger.

Before sending it:

- Run `sh tests/run.sh` and `git diff --check`.
- Keep Vim 8.2 compatibility unless the change deliberately raises the
  baseline.
- Keep public mappings and commands about Onesimus actions, not whichever
  plugin happens to provide them.
- Let optional integrations load only when they become useful, and fail back
  to ordinary Vim without stealing its behaviour.
- Preserve user files during installation and update; ambiguous destructive
  migrations should stop and explain themselves.

Vimscript uses two-space indentation and follows the surrounding file. Comment
rule lines use `" ------ ------`. The
[Google Vimscript Style Guide](https://google.github.io/styleguide/vimscriptguide.xml)
and [vint](https://github.com/Vimjas/vint) are useful references, not a reason
to rewrite unrelated code.

## Contributors

<a href="https://github.com/BaksiLi" target="_blank" title="BaksiLi">
<img src="https://github.com/BaksiLi.png?size=64" width="64" height="64" alt="BaksiLi"></a>

<a href="https://github.com/johanok" target="_blank" title="johanok">
<img src="https://github.com/johanok.png?size=64" width="64" height="64" alt="johanok"></a>
