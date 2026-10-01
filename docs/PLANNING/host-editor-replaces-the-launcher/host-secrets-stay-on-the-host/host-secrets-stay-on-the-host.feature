# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it, so
# nothing here is enforced by existing. What holds the code to it is a test per
# scenario, named for the scenario, in the repository whose CI runs it.
#
# Scenarios tagged @manual are confirmed by a person. Two kinds need that here:
# anything an editor window has to be open for, and the one mechanism no agent
# can observe, because ai-jail masks bwrap inside its own sandbox and so refuses
# to nest. The story's Acceptance criteria section carries that command.

Feature: Host secrets stay on the host
  An agent working in the sandbox cannot reach the credentials and agents that
  belong to the person at the keyboard, and cannot write the two configuration
  files that would let it run something outside the sandbox.

  Background:
    Given a project opened in the host's editor and connected to its container

  Scenario: The agent cannot reach the host's gpg agent
    When an agent in the sandbox looks for a gpg agent
    Then it finds none
    And the variables that would point it at one are absent

  Scenario: The agent cannot reach the host's display
    When an agent in the sandbox looks for a display
    Then it finds none

  Scenario: The agent cannot reach an ssh agent
    # Already true before this story, and nobody knew: no socket exists
    # anywhere in the container. Written down so that it staying true is a
    # criterion rather than a coincidence.
    When an agent in the sandbox looks for an ssh agent
    Then it finds none

  Scenario: A credential is never handed over as a variable
    When the sandbox is started for any agent
    Then no name carrying a secret is passed into it as an environment variable
    And any name that is passed has been decided about in advance

  Scenario: The container authenticates as itself
    When git inside the container needs a credential
    Then it asks the container's own GitHub CLI
    And no credential helper belonging to the host is consulted
    And the host's git identity is not present

  Scenario: The container's authentication is asserted, not assumed
    Given a container whose git configuration has had a foreign credential helper written into it
    When the container starts
    Then the helper is the container's own again
    And the change is reported once, naming what it replaced

  Scenario: The agent cannot write the editor's configuration
    # A task with runOn:folderOpen planted here would execute outside the
    # sandbox, with the person's own privileges.
    When an agent in the sandbox tries to write into the project's editor configuration
    Then the write is refused
    And the existing configuration is unchanged

  Scenario: The agent cannot write the container's own configuration
    # Worse than the above: a postCreateCommand planted here runs at container
    # creation, with the tooling's privileges, and the file is generated and
    # gitignored so no diff review would catch it.
    When an agent in the sandbox tries to write into the project's dev container configuration
    Then the write is refused
    And the existing configuration is unchanged

  @manual
  Scenario: A person can still write both
    # The escape, and it needs no mechanism: the editor runs on the host,
    # outside the sandbox.
    Given a person editing the project in the host's editor
    When they add a launch configuration by hand
    Then it is written
    And the agent can read it

  @manual
  Scenario: Workspace Trust is never disabled
    When a project is opened through the extension
    Then Workspace Trust is still enabled
    And no setting that disables it has been written by the extension
