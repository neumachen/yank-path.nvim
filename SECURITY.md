# Security Policy

## Supported Versions

Only the latest published minor version of `yank-path.nvim` receives security
updates. Older minors are not patched; please upgrade before reporting issues
against them.

| Version       | Supported          |
| ------------- | ------------------ |
| latest minor  | :white_check_mark: |
| older minors  | :x:                |

## Reporting a Vulnerability

Please report suspected vulnerabilities privately via GitHub Security
Advisories so the issue can be triaged and fixed before public disclosure:

<https://github.com/neumachen/yank-path.nvim/security/advisories/new>

When reporting, include:

- A clear description of the vulnerability and its impact
- Reproduction steps or a minimal proof-of-concept
- The affected version (`git rev-parse HEAD` or tag)
- Your Neovim version (`nvim --version`)

You can expect an initial response within seven days. Coordinated disclosure
timelines are agreed on a per-report basis.

## Out of Scope

- Issues that require an already-compromised editor environment
- Issues in third-party picker backends (`fzf-lua`, `snacks.nvim`) — please
  report those upstream
- Denial-of-service caused by user-supplied strategies that loop or consume
  memory; user strategies run inside the editor process and are trusted code
