## DevOps Scripts

These are scripts I've picked up or written that have been lifesavers in one way or another. 

### clean-up-retained-builds.ps1

Azure DevOps will not allow you to delete a build if it's retained by a release- but, they will allow you to remove a release that is retaining a build. This puts your organization in a state where you cannot adjust the retention policy for that release since it's deleted, you must clear all the retention locks on the build before deleting by hand or by script. This script takes parameters and runs against Azure DevOps organization to clean up retained builds linked to a specific repository in order to allow for build definition deletion.