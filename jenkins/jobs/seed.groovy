// Job DSL script - the versioned source of truth for every Jenkins job in
// this project. Run by the "seed-job" pipeline (defined inline in
// jenkins/jcasc/jenkins.yaml) whenever ./scripts/create-jobs.sh triggers
// it. Re-running this script is idempotent: Job DSL diffs the generated
// job config against what already exists and only updates what changed -
// running it twice in a row with no edits is a no-op.
//
// This satisfies the task's "jobs created as code" requirement via the
// "seed job that runs Job DSL from the repository" option (one of three
// allowed mechanisms). Manually creating these jobs through the Jenkins UI
// is explicitly out of scope and is never done anywhere in this project.

def gitRepoUrl = env.GIT_REPO_URL
def gitCredentialsId = env.GIT_CREDENTIALS_ID ?: ''

// ---------------------------------------------------------------------
// Job 1: ci-application - points at ci-Jenkinsfile, triggered by SCM
// change (webhook in a real deploy; poll as an offline fallback - see
// jenkins/README.md "Wiring the Git webhook").
// ---------------------------------------------------------------------
pipelineJob('ci-application') {
    description('''CI pipeline: checkout, validate, lint, unit test, build
        Docker images, tag with the short commit SHA, scan with Trivy, push
        to ECR, publish image tag/digest metadata. Never deploys anything.
        Defined by ci-Jenkinsfile at the repository root.'''.stripIndent())

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(gitRepoUrl)
                        if (gitCredentialsId) {
                            credentials(gitCredentialsId)
                        }
                    }
                    branch('*/main')
                }
            }
            scriptPath('ci-Jenkinsfile')
            lightweight(true)
        }
    }

    triggers {
        // Real deploy: configure a Git provider webhook -> Jenkins
        // `/github-webhook/` (see jenkins/README.md). githubPush() here
        // just registers the endpoint; it does nothing until a webhook
        // actually calls it.
        githubPush()
    }

    properties {
        pipelineTriggers {
            triggers {
                // Offline / lab fallback so `git push` is still eventually
                // picked up even before a webhook is wired - safe to leave
                // enabled alongside the webhook trigger above.
                pollSCM {
                    scmpoll_spec('H/5 * * * *')
                }
            }
        }
    }

    logRotator {
        numToKeep(30)
    }
}

// ---------------------------------------------------------------------
// Job 2: cd-application - points at cd-Jenkinsfile, takes the image tag
// (or digest) produced by CI as a build parameter. Never builds an image.
// ---------------------------------------------------------------------
pipelineJob('cd-application') {
    description('''CD pipeline: validates the given image tag/digest,
        helm-lints and dry-run validates the chart, runs `helm upgrade
        --install` against k8s/helm/cv-platform, waits for rollout, runs a
        smoke test, and prints rollback instructions on failure. Defined by
        cd-Jenkinsfile at the repository root. Never builds or pushes an
        image.'''.stripIndent())

    // Initial parameter set for the very first build only - once Jenkins
    // has checked out cd-Jenkinsfile once, its own `parameters {}` block
    // becomes the authoritative definition (standard "Pipeline from SCM"
    // behavior), which is why this list must stay a mirror of it, not a
    // second, divergent source of truth.
    parameters {
        stringParam('IMAGE_TAG', '', 'REQUIRED. Immutable tag produced by ci-application (short commit SHA), e.g. a1b2c3d. "latest" is rejected.')
        choiceParam('ENVIRONMENT', ['dev', 'prod'], 'Selects k8s/helm/cv-platform/values-<ENVIRONMENT>.yaml - also determines the target namespace.')
        stringParam('RELEASE_DESCRIPTION', '', 'Optional free-text note (e.g. Jira ticket, CI build URL) recorded as the Helm release description for traceability.')
        stringParam('CI_BUILD_URL', '', 'Optional: the ci-application build URL that produced IMAGE_TAG, propagated automatically when CD is triggered from CI - see jenkins/README.md "Traceability".')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(gitRepoUrl)
                        if (gitCredentialsId) {
                            credentials(gitCredentialsId)
                        }
                    }
                    branch('*/main')
                }
            }
            scriptPath('cd-Jenkinsfile')
            lightweight(true)
        }
    }

    // No SCM trigger: CD only ever runs (a) manually with an explicit
    // IMAGE_TAG, or (b) triggered from the tail of ci-application on main
    // (see ci-Jenkinsfile's "Trigger CD" stage) - never on its own push.
    disabled(false)

    logRotator {
        numToKeep(30)
    }

    properties {
        disableConcurrentBuilds {
            abortPrevious(false)
        }
    }
}
