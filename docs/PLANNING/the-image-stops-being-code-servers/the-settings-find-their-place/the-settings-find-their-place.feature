# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it.
# What holds the code to it is a test per scenario, named for the scenario, in
# this repository's CI.
#
# Nothing here is @manual, which is unusual for this epic's neighbours and is
# the point: every claim is about what the image declares and what the
# repository contains. A person looking at an editor would add nothing.

Feature: The settings find their place
  One of the seven settings this image seeded for code-server survives, in the
  image's own metadata, and the machinery that delivered the rest is gone.

  Scenario: The setting that belongs to a declared extension survives
    Given the image declares the file-icons extension
    When the composed label is read
    Then it declares the icon theme setting

  Scenario: Nothing else reaches the editor
    When the composed label is read
    Then it declares no other editor setting

  Scenario: The seeding machinery is gone
    When the repository is examined
    Then no file seeds editor settings into the container
    And no boot hook rewrites them
    And no job remains to test either

  Scenario: The required check still covers every job
    # Removing a job and leaving its name in the aggregator's needs list makes
    # the whole workflow invalid, which fails every pull request including the
    # one that would fix it.
    Given a job has been removed from the workflow
    When the required check's coverage is examined
    Then it names no job that does not exist
    And every job that exists is named

  Scenario: A setting that cannot be set from a container is not declared
    # window.menuBarVisibility is application-scoped: a container cannot set it
    # at any price, and the desktop build's default is already the value this
    # image used to seed.
    When the composed label is read
    Then it declares no application-scoped setting

  Scenario: The symptom outlives the setting
    # The renderer race that gpuAcceleration:off worked around was real and
    # measured. Whoever meets it on the host has to be able to recognise it.
    Given a setting was removed that worked around a measured defect
    When the documentation is read
    Then the symptom is still described
    And it says the setting is the reader's own to make
