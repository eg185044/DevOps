{{/*
student-web.name - the chart's base name (override with .Values.nameOverride).
*/}}
{{- define "student-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
student-web.fullname - the release-qualified name every resource is
prefixed with (e.g. release "student-web-dev" -> "student-web-dev-...").
If the release name already contains the chart name, don't repeat it -
this is the same logic `helm create` scaffolds by default.
*/}}
{{- define "student-web.fullname" -}}
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
student-web.labels - the full, informational label set (safe to change on
every upgrade). Stamped on every resource's metadata.labels.
*/}}
{{- define "student-web.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "student-web.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
student-web.selectorLabels - the minimal, IMMUTABLE label set used for
object *selection* (Deployment.spec.selector, Service.spec.selector). Never
add anything here that could change between upgrades - Deployment selectors
are immutable after creation, so a selector-label change breaks `helm upgrade`.
*/}}
{{- define "student-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "student-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
