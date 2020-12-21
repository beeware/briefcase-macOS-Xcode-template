Briefcase macOS XCode Template
============================

A `Cookiecutter <https://github.com/cookiecutter/cookiecutter/>`__ template for
building Python apps that will run under macOS, using an Xcode project to
control the entry-point binary.

The easiest way to use this project is to not use it at all - at least, not
directly. `Briefcase <https://github.com/beeware/briefcase/>`__ is a tool that
uses this template, rolling it out using data extracted from a
``pyproject.toml`` configuration file.

The master branch of this repository has no content; there is an independent
branch for each supported version of Python. The following Python versions are
supported:

* `Python 3.6 <https://github.com/beeware/briefcase-macOS-Xcode-template/tree/3.6>`__
* `Python 3.7 <https://github.com/beeware/briefcase-macOS-Xcode-template/tree/3.7>`__
* `Python 3.8 <https://github.com/beeware/briefcase-macOS-Xcode-template/tree/3.8>`__

Suggestions for template changes should be made against the `dev branch
<https://github.com/beeware/briefcase-macOS-Xcode-template/tree/dev>`__; these
will then be backported into the supported Python releases. The dev branch will
track the most recent supported version of Python (currently, Python 3.8).

See the individual branches for usage instructions.
