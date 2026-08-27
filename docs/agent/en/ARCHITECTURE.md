# Writing the architecture overview

How to write and keep `docs/ARCHITECTURE/OVERVIEW.md` in a project built on this template. That
file describes what the system is, right now: its parts, what each one owns, how they reach each
other, and where it breaks — written so that someone arriving on their first day can find the seam
they need without reading the code first.

**This file is the instruction; the project's file is the content.** The two are kept apart on
purpose: a preamble explaining how to write a document is useful exactly once, and after that it is
noise sitting on top of what the reader came for. Paths outside this folder are written as code
rather than as links, for the reason given in [Rules](RULES.md).

## What this is not

- **Not the dev environment's architecture.** The container, the sandbox, the nested Docker daemon
  and the launcher belong to the template, and they are documented in
  `.code-server/docs/overview/`, which versions with the template rather than with the project.
  Do not restate it there; link it.
- **Not a decision log.** Why a shape was chosen, what was rejected, and what it cost live in the
  project's `docs/RFC/`, and stay true after the code moves on. The architecture file describes the
  present and is rewritten whenever the present changes.
- **Not `docs/OVERVIEW.md`**, which is how to use the template as a consumer. Several files in a
  project are called `OVERVIEW.md`; check which one you are editing.

## Keeping it true

An architecture document that lags the system is worse than none, because it is believed. The rule
that keeps it honest: **an RFC that changes the shape updates the architecture file in the same
pull request.** The RFC says why it changed; the architecture file says what it is now. If they
disagree, the architecture file is wrong.

## Sections to fill

A project fills these in as it grows. Empty is a fine answer while something does not exist yet;
a section that quietly describes an intention rather than the code is not.

### Context and boundaries

What the system is responsible for and what it deliberately is not. Who and what it talks to across
its edges — users, other services, third parties — and which of those it trusts.

### Components

One entry per part that can fail independently. What it owns, what it depends on, and what it would
take down with it. Name the thing that is not obvious from the directory layout.

### Data

What is stored, where, and for how long. If the project processes personal data, this is the same
map recorded in RFC `0001` — keep one of them and link the other, never two that can disagree. See
Security in [Rules](RULES.md).

### Runtime and deployment

How it runs in production and how that differs from how it runs here. Where configuration comes
from, what is required to be present, and what it does when something is missing.

### Failure modes and observability

How the system fails, how anyone finds out, and what they look at first. The three worst failure
scenarios named in each RFC accumulate here once they are real, along with the signals that catch
them — see Observability in [Rules](RULES.md).

### Seams

Where the system was deliberately left able to change: the i18n catalogue, the theming and
accessibility tokens, an interface with a second implementation in mind. A seam nobody documents
is a seam the next change routes around.

### Open edges

What is known to be unfinished or wrong, and what it would take to close. This is the section that
makes the rest trustworthy: a document with no open edges is either finished or unmaintained, and
it is rarely finished.

---

**The project's file starts nearly empty, and that is correct.** A section with nothing under it
says the thing does not exist yet; a section quietly describing an intention says something false.
Fill them as the system grows.
