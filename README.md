# project-sync

utility script that stores a snapshot of the current git state of all repositories belonging to a specific grouping of repositories, identified by freely chosen groupname.
Its purpose is simply to restore a collection of git repositories used together in 1 application to a specific point of collective usage.

requires:
---------
- git 
- jq
- bash

usage:
------
./project-sync.sh *command* [*argument*..]

commands:
---------
- init: install data folder
- expunge: remove data folder
- add-project-group *groupname*: add current repository to group
- remove-repository *groupname* *repository path*: remove repository from group
- remove-group *groupname*: remove group (and repositories linked to t)
- list-repositories *groupname*: list repositories linked to group
- add-snapshot *groupname*: save git state snapshot of all repositories linked to group
- checkout-snapshot *groupname*: checkout the git state found in last snapshot for the repositories other than this current one and based on current one.

Example usage:
--------------

    ./project-sync.sh init

this creates the data file at ~/.project-sync/  (you only need to do this once ever)

go to all git repository directory you want to add to a group and do
    ./project-sync.sh add-project-group "my easy to remember groupname for this collection of repositories"

as long as the groupname is identical the repositories will land up in one grouping


whenever you wish to record a new state, do 
    ./project-sync.sh add-snapshot "my easy to remember groupname for this collection of repositories"

whenever you wish to restore any of such states, do
    ./project-sync.sh checkout-snapshot "my easy to remember groupname for this collection of repositories"

from inside one of the repositories. This repository will serve as the basis on which the corresponding last snapshot is chosen.


so if you have snapshots with 2 repositories:

    repo1       repo2
    branch Q    branch W
    branch S    branch T

and you move into repo2 to checkout while repo2 is on branch W then repo1 wil get checked out on branch Q, likewise if repo2 would be T then repo1 would become S.
Comparison is first done on branch, if the branch has moved on beyond the snapshot point then the specific commit is checked out (HEADLESS branch checkout)
