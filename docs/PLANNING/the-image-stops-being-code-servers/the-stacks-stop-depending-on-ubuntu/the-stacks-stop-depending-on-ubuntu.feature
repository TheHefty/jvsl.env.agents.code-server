# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it.
# What holds the code to it is a test per scenario, named for the scenario, in
# this repository's CI.
#
# Nothing here is @manual. Both stacks have image builds, and every claim is
# about what a built image contains and can do.

Feature: The stacks stop depending on Ubuntu
  No stack adds a package repository that only one distribution has, so the base
  image can change without a stack breaking on a dists path that does not exist.

  Scenario: No stack adds an Ubuntu-only repository
    # The step said "a Launchpad PPA" while the story's title says "Ubuntu", and
    # the guard that implements it is broader than either: it refuses any
    # hardcoded distribution or codename in a repository path, because `dotnet`
    # had `config/ubuntu/24.04` and no PPA. The narrow step was the defect — it
    # would have passed with the dependency still there.
    When the Dockerfile fragments are examined
    Then none of them names a distribution or codename in a repository path

  Scenario: PHP still installs the version the manifest asked for
    Given a project selecting a PHP version
    When its image is built
    Then that version of PHP answers
    And composer answers

  Scenario: Python still installs each version the stack lists
    # The stack lists three. The distribution the base is moving to packages one
    # of them, which is the whole reason this story exists.
    Given a project selecting any version the python stack lists
    When its image is built
    Then that version answers as python3

  Scenario: Python can still build a package that compiles
    # An interpreter that runs is not the test. The stack installs development
    # headers today, and a task that installed only an interpreter would pass a
    # version check and fail the first pip install that compiles anything.
    Given an image built from the python stack
    When a package that compiles a C extension is installed
    Then it builds and imports

  Scenario: A repository that does not serve the base fails at build time
    # The failure this story exists to prevent is silent only in prose: apt 404s
    # on a dists path and says nothing about the distribution. Whatever each
    # stack ends up using has to fail where it is configured, not later.
    Given a fragment configured for a distribution the base is not
    When the image is built
    Then the build fails naming the repository
