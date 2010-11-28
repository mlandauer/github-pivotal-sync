Two-way synchronisation of GitHub issues with Pivotal Tracker stories.

GitHub - https://www.github.com
Pivotal Tracker - https://www.pivotaltracker.com/

Create a bunch of issues in GitHub issues or Pivotal Tracker and synch them across by running this tool. After the first synchronisation, change the title of an issue in GitHub and it changes in Pivotal Tracker.

Currently issues are only created or edited. They are not deleted. So, closing a ticket in GitHub will not do anything to Pivotal Tracker.

To install the required gems:
$ bundle install

To configure:
$ cp configuration-example.yaml configuration.yaml

You will need to edit the configuration.yaml file with the details of the GitHub account and repository and Pivotal Tracker account and project you will be synching.

To run:
$ ./sync.rb