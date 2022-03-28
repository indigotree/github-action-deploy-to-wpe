FROM instrumentisto/rsync-ssh:alpine3.13-r4
LABEL "com.github.actions.name"="GitHub Action to deploy WordPress projects to WP Engine"
LABEL "com.github.actions.description"="An action used to deploy code from a GitHub repo to a WP Engine environment of your choosing"
LABEL "com.github.actions.icon"="upload-cloud"
LABEL "com.github.actions.color"="purple"
LABEL "repository"="https://github.com/indigotree/github-action-deploy-to-wpe"
LABEL "maintainer"="Paul Wong-Gibbs <paul.wong-gibbs@indigotree.co.uk>"
RUN apk add bash php
ADD entrypoint.sh /entrypoint.sh
ADD exclude.txt /exclude.txt
ENTRYPOINT ["/entrypoint.sh"]
