# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it.
# What holds the code to it is a test per scenario, named for the scenario, in
# this repository's CI.
#
# Most of these are assertions about absence, which is a shape worth being
# careful with: a test that something is gone passes trivially once it is gone,
# and would also pass if the test itself stopped looking. Each one below names
# what must still be present alongside what must not, so that a check which has
# stopped working looks different from a check that is satisfied.

Feature: The launcher is gone
  `start` is deleted, and so is everything that existed only to build or run
  it. Opening a project in the host's editor is the only way in.

  Scenario: Nothing in the repository builds or runs the launcher
    When the repository is examined
    Then there is no launcher crate
    And no script builds or runs one
    And nothing in the documentation offers it as a way in

  Scenario: The host no longer needs Rust to use this template
    Given a host with jq, whiptail and docker and no cargo
    When the setup helper is run
    Then it does not ask for cargo
    And it builds the image

  Scenario: The host's remaining prerequisites are still named
    # The counterpart to the scenario above. Removing a prerequisite check is
    # one edit away from removing all of them, and a helper that checks nothing
    # fails later and says less.
    Given a host missing one of jq, whiptail or docker
    When the setup helper is run
    Then it names which one is missing and what to do about it

  Scenario: The image no longer carries the launcher's libraries
    When the image is inspected
    Then the Tauri development libraries are absent

  Scenario: The Rust toolchain survives in the image
    # The thing that looks like it belongs to the launcher and does not: the
    # rust stack depends on core's rustup rather than installing its own, and
    # the sandbox is handed RUSTUP_HOME because a cargo on PATH without it is a
    # shim that cannot find its toolchain.
    Given an image composed with the rust stack
    When a toolchain is asked for inside it
    Then rustup answers
    And an agent in the sandbox can run cargo

  Scenario: CI has no job left for the launcher
    When the workflow is examined
    Then no job builds or checks a launcher
    And every job that remains is still covered by the required check

  Scenario: A consuming repository is told what changed
    Given a project bumping the template across this major
    When it reads what the release changed
    Then it is told the launcher is gone and what to use instead
    And it is told Rust is no longer required on the host

  @manual
  Scenario: A project still opens with no launcher present
    Given a working copy with no launcher anywhere in it
    When the project is opened in the host's editor
    Then the container comes up and the editor attaches as before
