# Acceptance criteria for the story beside this file.
#
# Documentation first, and not executable: no Gherkin runner is wired to it.
# What holds the code to it is a test per scenario, named for the scenario, in
# the repository whose CI runs it.
#
# One scenario is @manual, for the usual reason: no CI available to either
# repository can look at an editor's installed extensions. The rest are
# assertions about the composed image, which CI can make.

Feature: The remote editor arrives equipped
  Opening a project gives the editor on the host the extensions the image
  associates with that project's stacks — without the project listing anything,
  and without the extension's own repository knowing which stack needs what.

  Scenario: The image declares what a project's stacks imply
    Given an image composed for a project with a stack that wants an extension
    When the image is inspected
    Then it declares that extension as one the editor should install

  Scenario: Several stacks contribute without overwriting each other
    # A later LABEL replaces an earlier one, so nine stacks losing their
    # extensions while the tenth keeps them is the failure this exists to stop —
    # and it fails nothing while happening.
    Given an image composed for a project with three stacks that each want one
    When the image is inspected
    Then all three extensions are declared

  Scenario: No fragment declares the label, and the composed image declares one
    When the Dockerfile fragments are examined
    Then none of them declares the metadata label
    And the composed Dockerfile declares exactly one
    And it still names the unprivileged user, and no container user

  Scenario: A stack that wants nothing changes nothing
    Given an image composed for a project with a stack that declares no extensions
    When the image is inspected
    Then the declaration is the same as for a project with no stacks at all

  Scenario: Adding a stack to the template adds its extension
    # The point of the list living in the image: the extension's repository has
    # no table of stacks to keep in step.
    Given a stack newly added to the template, declaring an extension
    When a project selects it and the image is composed
    Then that extension is declared, with no change made in the extension's repository

  Scenario: The declared list is not a translation of the other one
    # The one case where the remote list can be better rather than different:
    # the first-party extension is licensed for the editor this epic committed
    # to, which is why a fork of it exists on the other registry at all.
    Given a project with the .NET stack
    When the image is inspected
    Then the declared extension is the one published by the language's vendor
    And it is not the identifier the code-server list installs

  Scenario: Every declared extension exists where the editor will look for it
    When the declared extensions are checked against the editor's registry
    Then each one is found

  Scenario: An extension that cannot be resolved does not stop the project opening
    Given a declaration naming an extension that the registry does not have
    When the project is opened
    Then the project opens
    And the failure is reported rather than silent

  @manual
  Scenario: The extensions are actually there
    Given a project opened in the host's editor and connected to its container
    When the installed extensions are listed
    Then the ones its stacks imply are present
    And the Gherkin support among them, so this process's own files are readable
