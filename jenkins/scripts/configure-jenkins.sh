#!/usr/bin/env bash
# Re-applies configuration to an ALREADY-INSTALLED Jenkins: RBAC,
# NetworkPolicies, and a `helm upgrade` that picks up any change to
# jenkins/jcasc/jenkins.yaml, jenkins/helm/values.yaml, or
# jenkins/plugins.txt. Does not touch the admin credential Secret or the
# namespaces (those are one-time bootstrap concerns - see
# install-jenkins.sh).
#
# In short: install-jenkins.sh's steps are all individually idempotent, so
# "configure" is simply "re-run install with the same inputs" - kept as a
# separate, named script only because the task requires
# install/configure/create-jobs/verify as four distinct entry points.
#
# Usage: same required env vars as install-jenkins.sh.
set -euo pipefail
cd "$(dirname "$0")"
exec ./install-jenkins.sh
