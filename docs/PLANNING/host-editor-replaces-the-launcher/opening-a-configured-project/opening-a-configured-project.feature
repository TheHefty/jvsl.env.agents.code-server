# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to this
# file, so nothing here is enforced by CI merely by existing. What holds the
# code to it is a test per scenario, named for the scenario, in the repository
# whose CI runs it.
#
# Scenarios tagged @manual are confirmed by a person on a host with the editor
# installed. Neither repository has CI that can observe an editor window, and
# a criterion everyone assumes is covered is worse than one that says it is not.

Feature: Opening a configured project
  A project that already carries the template opens in the editor running on the
  host, connected to that project's own container, as the user the container is
  meant to run as — with the machine limits the project asked for and only the
  devices the host actually has.

  Background:
    Given a project whose repository carries the template as a submodule
    And an image already built for that project

  Scenario: The container's own user can be logged in as
    When the image is inspected
    Then its unprivileged user has a usable login shell

  Scenario: The image declares who it should be entered as
    When the image is inspected
    Then it declares its unprivileged user as the one a dev container client connects as
    And the configuration generated for opening does not override that declaration

  @manual
  Scenario: Opening the project connects the editor to its container
    Given the extension is installed in the host's editor
    When the project is opened
    Then the editor is connected to that project's container
    And the workspace is the project's own directory inside it

  @manual
  Scenario: The very first connection is not root
    Given a project whose container has never been connected to
    When the project is opened for the first time
    And a terminal is started in it
    Then that terminal runs as the container's unprivileged user
    And no directory the editor created belongs to anyone else

  Scenario: An environment damaged by an earlier connection is repaired
    Given an existing environment whose editor and gpg state directories belong to root
    When the container starts
    Then those directories belong to the unprivileged user
    And the repair is reported once, naming what it changed

  Scenario: Repairing is safe to repeat
    Given an environment whose state directories already belong to the unprivileged user
    When the container starts twice
    Then nothing is changed on either start
    And nothing is reported

  Scenario: The project gets the machine it asked for
    Given a project whose manifest asks for a number of cores and an amount of memory
    When the project is opened
    Then the container is restricted to that many cores
    And to that much memory
    And a tool inside the container that counts processors sees the restricted number

  Scenario: A project that asks for nothing gets what the launcher gave it
    Given a project whose manifest declares no limits
    When the project is opened
    Then the container is restricted to half the host's cores
    And to the memory the launcher used before manifests could ask

  Scenario: Only devices the host actually has are passed through
    Given a host without hardware virtualization
    When the project is opened
    Then the project opens
    And the container is created without that device

  Scenario: The editor is not subject to the container's limits
    Given a project restricted to a subset of the host's cores
    When the project is open and a build is running inside the container
    Then the editor's own process is not restricted to those cores
    And it is not subject to the container's memory limit
