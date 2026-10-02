# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it.
# What holds the code to it is a test per scenario, named for the scenario, in
# this repository's CI.
#
# One scenario is @manual and cannot be otherwise: no CI available to either
# repository attaches an editor to a container. Everything else is an assertion
# about a built image.

Feature: The base carries no editor
  The image is built on a base that carries the conventions this template needs
  and no editor, and nothing left in it is an editor's.

  Scenario: The image carries no editor
    When the image is inspected
    Then there is no code-server in it
    And nothing in it installs editor extensions

  Scenario: The conventions the template depends on are still there
    # The whole epic rests on these arriving from the base. If the base ever
    # stops providing one, every ownership and isolation decision above it is
    # affected, and the failure would otherwise surface as something unrelated.
    When the image is inspected
    Then the unprivileged user exists with the home this template expects
    And the service supervisor is present
    And the mechanism that runs boot hooks is present

  Scenario: Every stack still builds
    Given a stack selected from the manifest
    When its image is composed and built
    Then the build succeeds
    And the stack's own checks pass

  Scenario: The Rust toolchain survives
    # Third story in a row this is asserted, because it sits where the editor's
    # libraries sat and is the thing most likely to go with them.
    When a toolchain is asked for inside the image
    Then rustup answers

  Scenario: The leftover editor state is removed from a volume that has it
    Given a volume carrying the previous editor's state
    When the container starts
    Then the state is removed
    And what was removed is reported

  Scenario: Something unrecognised in those paths is left alone
    # The hook deletes from somebody's volume. It identifies what it removes
    # rather than presuming a path's contents, and when it cannot it refuses.
    Given a volume where one of those paths holds something else
    When the container starts
    Then it is not removed
    And the reason is reported

  Scenario: A volume that never had it is untouched and silent
    Given a volume with no previous editor state
    When the container starts
    Then nothing is removed and nothing is said about it

  Scenario: The documentation describes no editor in the container
    When the documentation is read
    Then no unauthenticated editor server is described as running there
    And the security record no longer claims one

  @manual
  Scenario: A project still opens on the new base
    Given a project whose image was built on the editor-free base
    When it is opened in the host's editor
    Then the container comes up and the editor attaches as before
