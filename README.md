maven-release-script
====================

This script provides similar functionality to the Maven release script, but works nicely with git.

I created the script because to get the maven release plugin to work the way I wanted meant keeping a version of Maven 2.0 and not using concurrent builds; this was a huge pain.

Usage
=====

```
Usage:
  release.sh [-a -b | [ -r RELEASE_VERSION ] [ -n NEXT_DEV_VERSION ] ]  [ -c ASSUMED_POM_VERSION ] [ -m NEXT_REL_BRANCH_VERSION ]
Updates release version, then builds and commits it

  -a    Shorthand for -a auto -n auto
  -r    Sets the release version number to use ('auto' to use the version in pom.xml)
  -n    Sets the next development version number to use (or 'auto' to increment release version)
  -m    Sets the version in release branch 
  -c    Assume this as pom.xml version without inspecting it with xmllint
  -b    Assume simple release of bugfix version
  -h    For this message
```

Dependencies
============

Following tools must be setup for script to work:

  * Apache Maven 3+ https://maven.apache.org/download.cgi
  * xmllint from libxml2-utils. Ubuntu installation `sudo apt-get install libxml2-utils`
  * following maven plugins should be accessible via maven:
    ** lt.omnitel.maven.plugins:archiva-plugin:0.0.1-SNAPSHOT
    ** org.apache.maven.plugins:maven-release-plugin:2.3.2
  
