{{/*
cv-platform.name - the chart's base name (override with .Values.nameOverride).
*/}}
{{- define "cv-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
cv-platform.fullname - the release-qualified name every resource is prefixed
with, so `helm install cv-platform-dev ./k8s/helm/cv-platform` and
`helm install cv-platform-prod ./k8s/helm/cv-platform` never collide even if
they ever land in the same namespace. Standard `helm create` scaffold logic:
if the release name already contains the chart name, don't repeat it.
Override outright with .Values.fullnameOverride if needed.
*/}}
{{- define "cv-platform.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
cv-platform.labels - the full label set stamped on every resource's
metadata.labels (informational: safe to change on every upgrade). Includes
the required app.kubernetes.io/* convention plus this project's own
env/part-of labels. Not used for object *selection* - see selectorLabels
below for that.
*/}}
{{- define "cv-platform.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "cv-platform.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: erez-cv-platform
env: {{ .Values.config.environment | default "production" }}
{{- end -}}

{{/*
cv-platform.selectorLabels - the minimal, IMMUTABLE label set used anywhere
Kubernetes has to *match* Pods: Deployment/spec.selector, Service/spec.selector,
NetworkPolicy podSelector. Never add anything here that could change between
helm upgrades (e.g. version, env) - Deployment.spec.selector is immutable
after creation, so an upgrade that touched a selector label would fail.
*/}}
{{- define "cv-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cv-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
cv-platform.componentLabels - cv-platform.labels plus a per-component
app.kubernetes.io/component label (frontend/backend/worker/redis-cache/...).
Usage: {{ include "cv-platform.componentLabels" (dict "context" . "component" "backend") | nindent 4 }}
*/}}
{{- define "cv-platform.componentLabels" -}}
{{ include "cv-platform.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
cv-platform.componentSelectorLabels - cv-platform.selectorLabels plus the
same per-component label, for the places that need to *match* one specific
component's Pods (matchLabels / Service selector / NetworkPolicy podSelector).
Usage: {{ include "cv-platform.componentSelectorLabels" (dict "context" . "component" "backend") | nindent 6 }}
*/}}
{{- define "cv-platform.componentSelectorLabels" -}}
{{ include "cv-platform.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}
