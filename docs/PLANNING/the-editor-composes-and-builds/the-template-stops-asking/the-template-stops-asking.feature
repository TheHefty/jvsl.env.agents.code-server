# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it.
# What holds the code to it is a test per scenario, named for the scenario, in
# this repository's CI.
#
# Nothing here is tagged @manual, which is new for this epic. The interactive
# path is driven by feeding standard input — simpler than what it replaces,
# since the whiptail path needed a stub binary with canned answers and a read
# loop needs nothing.

Feature: The template stops asking
  `whiptail` is retired. `setup` asks the same five questions with plain shell
  prompts when a person is there to answer, and reads the manifest when nobody
  is — which is how the editor drives it.

  Scenario: With a terminal, the same five questions are asked
    Given a terminal
    When setup is run
    Then it asks which stacks, a version for each chosen stack, and the memory,
      swap and CPU limits
    And nothing it asks requires whiptail

  Scenario: Each question offers the current answer as its default
    # The whiptail path pre-checked the existing selection. Losing that would
    # make every rerun retype everything, which is how a tool stops being rerun.
    Given a project whose manifest already selects a stack and a version
    And a terminal
    When setup is run and every prompt is accepted without typing
    Then the manifest is unchanged

  Scenario: Without a terminal, nothing is asked
    Given no terminal
    When setup is run
    Then it asks nothing
    And it composes and builds from the manifest as it stands

  Scenario: A project with no manifest builds the core alone
    Given a project with no manifest
    And no terminal
    When setup is run
    Then an image with no stack in it is built
    And a manifest is written, so the next run infers nothing

  Scenario: A manifest that cannot be parsed stops everything
    Given a manifest that is not valid JSON
    When setup is run
    Then it refuses, naming the file
    And no image is built

  Scenario: An answer that is not valid is asked again
    # whiptail's menus made most of these unrepresentable. A read loop does not,
    # so the validation is the script's now and has to exist rather than be
    # inherited.
    Given a terminal
    When setup is run and a version no stack offers is typed
    Then the question is asked again
    And nothing is written until the answer is one the stack has

  Scenario: Nothing requires whiptail any more
    When the repository and the host prerequisites are examined
    Then whiptail is named nowhere as something to install
    And the host's prerequisites are jq and docker

  Scenario: What a project did not select is still not selected
    # The manifest holds keys setup does not own. Rewriting it from the answers
    # must not drop them, which is a regression this repository has already had.
    Given a manifest carrying a key setup does not write
    When setup is run and answers are given
    Then that key is still there afterwards
