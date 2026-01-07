# Homelab Cluster Applications
#
# This directory contains ArgoCD Application CRDs for the homelab cluster.
# The root-app.yaml implements the App of Apps pattern.
#
# Structure:
# - root-app.yaml     - Root Application (App of Apps pattern)
# - homepage.yaml     - Homepage dashboard
# - mqtt.yaml         - EMQX MQTT broker
# - vaultwarden.yaml  - Bitwarden-compatible password manager
# - platform.yaml     - Platform configs (MetalLB, alerts, etc.)
# - reloader.yaml     - Stakater Reloader (Helm)
#
# Adding a new application:
# 1. Create the app structure in k8s/apps/<app-name>/
# 2. Create an Application CRD here pointing to k8s/apps/<app-name>/
# 3. Commit and push - ArgoCD will auto-sync via root-app
#
# IMPORTANT: During cutover from old paths, pruning is disabled.
# Re-enable pruning after verifying all apps sync correctly.
