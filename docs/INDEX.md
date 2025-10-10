# VMStation Documentation Index

This index catalogs all documentation files consolidated during the manifest reorganization.

## Documentation Files

### Core Documentation

**QUICK_START.md**
- Title: VMStation Quick Start Guide
- Summary: This guide shows you how to quickly deploy the VMStation Kubernetes cluster using the simplified modular deployment commands.

**TODO.md**
- Title: VMStation TODO List
- Summary: clear

**architecture.md**
- Title: Architecture
- Summary: VMStation uses a **two-cluster architecture** to separate concerns and avoid OS mixing issues:

### Deployment Documentation

**DEPLOYMENT_FIXES_OCT2025.md**
- Title: Deployment Fixes - October 2025
- Summary: This document describes fixes applied to resolve deployment issues identified on October 7, 2025.

**DEPLOYMENT_FIXES_OCT2025_PART2.md**
- Title: VMStation Deployment Issues - Root Cause Analysis and Fixes
- Summary: **Date:** October 9, 2025  

**DEPLOYMENT_FIXES_SUMMARY.md**
- Title: VMStation Deployment Fixes Summary
- Summary: **Date**: 2025-10-09  

**DEPLOYMENT_ISSUE_RESOLUTION_SUMMARY.md**
- Title: VMStation Deployment Issues - Summary and Resolution
- Summary: Your deployment had **3 critical issues**:

**DEPLOYMENT_RUNBOOK.md**
- Title: VMStation Modular Deployment Runbook
- Summary: ---

**DEPLOYMENT_VALIDATION_REPORT.md**
- Title: VMStation Deployment Validation Report
- Summary: **Date**: 2025-10-08  

**SIMPLIFIED_DEPLOYMENT_IMPLEMENTATION.md**
- Title: Simplified Deployment Automation - Implementation Summary
- Summary: The latest PR created modular Ansible playbooks for monitoring and infrastructure services, but the deployment process was complex and required users ...

**deploy.md**
- Title: Deployment Guide
- Summary: 1. **Controller Machine** (masternode 192.168.4.63):

### Monitoring Documentation

**ENTERPRISE_MONITORING_ENHANCEMENT.md**
- Title: Enterprise-Grade Monitoring System Enhancement Summary
- Summary: This document summarizes the enterprise-grade enhancements made to the VMStation homelab monitoring and autosleep/wake system to meet production-level...

**HOMELAB_MONITORING_INTEGRATION.md**
- Title: Homelab Monitoring Integration Guide
- Summary: This guide explains how to integrate the homelab RHEL 10 node (running RKE2) with the VMStation masternode monitoring stack for centralized logging an...

**IPMI_MONITORING_GUIDE.md**
- Title: IPMI Monitoring Setup for RHEL 10 Enterprise Server
- Summary: This guide explains how to set up and configure IPMI (Intelligent Platform Management Interface) monitoring on the RHEL 10 homelab node for enterprise...

**LOKI_CONFIG_DRIFT_PREVENTION.md**
- Title: Loki ConfigMap Drift Prevention and Automation
- Summary: Loki pods were experiencing CrashLoopBackOff errors due to configuration drift between the repository and the in-cluster ConfigMap. The specific issue...

**LOKI_CONFIG_QUICK_START.md**
- Title: Loki ConfigMap Drift Prevention - Quick Start
- Summary: Loki pods crash with: `failed parsing config: field wal_directory not found in type storage.Config`

**LOKI_DRIFT_PREVENTION_IMPLEMENTATION.md**
- Title: Loki ConfigMap Drift Prevention - Implementation Summary
- Summary: This implementation addresses the Loki CrashLoopBackOff issue caused by configuration drift between the repository and in-cluster ConfigMap. The solut...

**LOKI_ENTERPRISE_REWRITE.md**
- Title: Loki Log Aggregation - Enterprise Rewrite Documentation
- Summary: This document details the comprehensive rewrite of the Loki log aggregation manifest to meet industry-standard best practices for production Kubernete...

**LOKI_FIX_QUICK_REFERENCE.md**
- Title: Quick Fix: Loki Deployment Issues
- Summary: 1. ✅ **Loki Query Error**: "parse error: queries require at least one regexp or equality matcher that does not have an empty-compatible value"

**LOKI_ISSUES_RESOLUTION.md**
- Title: Loki Deployment Issues - Resolution Summary
- Summary: Three critical issues were affecting the VMStation monitoring stack:

**MONITORING_ACCESS.md**
- Title: VMStation Monitoring Access Guide
- Summary: This document describes how to access monitoring endpoints without authentication for operational visibility.

**MONITORING_FIXES_README.md**
- Title: Monitoring Stack Fixes - October 2025
- Summary: ```bash

**MONITORING_FIX_SUMMARY.md**
- Title: Monitoring Deployment Fix - Complete Summary
- Summary: **Issue:** Phase 8 (Wake-on-LAN Validation) was positioned at line 36, between Phase 0 header (line 12) and Phase 1 (line 269). This caused Phase 8 to...

**MONITORING_IMPLEMENTATION_DETAILS.md**
- Title: Monitoring Stack Fix - Implementation Summary
- Summary: The VMStation monitoring stack exhibited complete data pipeline failure despite having Prometheus and Grafana deployed. All Grafana dashboard panels s...

**MONITORING_QUICK_REFERENCE.md**
- Title: Monitoring Stack Quick Reference
- Summary: | Service | URL | Authentication | Purpose |

**MONITORING_STACK_FIXES_OCT2025.md**
- Title: VMStation Monitoring Stack Fix Summary - October 2025
- Summary: Fixed three critical issues preventing successful cluster deployment:

**PROMETHEUS_ENTERPRISE_REWRITE.md**
- Title: Prometheus Monitoring Stack - Enterprise Rewrite Documentation
- Summary: This document details the comprehensive rewrite of the Prometheus monitoring manifest to meet industry-standard best practices for production Kubernet...

**QUICK_REFERENCE_MONITORING_FIXES.md**
- Title: Quick Reference: Monitoring Stack Fixes
- Summary: ```bash

**monitoring-pod-scheduling-solution.md**
- Title: Monitoring Pod Scheduling and RKE2 Installation Fix
- Summary: The deployment had two critical issues preventing successful cluster operation:

### Troubleshooting & Fixes

**CNI_PLUGIN_FIX_JAN2025.md**
- Title: CNI Plugin Installation Fix - January 2025
- Summary: The Jellyfin pod (and potentially other pods) on the `storagenodet3500` worker node was stuck in `Terminating` and `ContainerCreating` states with the...

**CRASHLOOPBACKOFF_FIXES_README.md**
- Title: CrashLoopBackOff Fixes - Quick Reference
- Summary: This document provides a quick overview of the monitoring stack CrashLoopBackOff fixes that have been implemented and verified in this repository.

**CRASHLOOPBACKOFF_FIXES_VERIFIED.md**
- Title: Monitoring Stack Fixes - Validation Report
- Summary: **Date**: October 9, 2025  

**PVC_FIX_OCT2025.md**
- Title: PersistentVolume Claims Fix - October 2025
- Summary: Multiple pods were stuck in `Pending` state due to unbound PersistentVolumeClaims (PVCs):

**PVC_FIX_SUMMARY.md**
- Title: PersistentVolume Claims Fix - Summary
- Summary: Multiple Kubernetes pods were stuck in `Pending` state due to unbound PersistentVolumeClaims (PVCs). The problem statement indicated:

**QUICK_START_FIXES.md**
- Title: Quick Start: Deployment Fixes
- Summary: This PR fixes critical deployment issues with Loki, Prometheus, and monitoring tests.

**TROUBLESHOOTING_GUIDE.md**
- Title: Enterprise Monitoring and Infrastructure - Troubleshooting Guide
- Summary: This guide provides step-by-step troubleshooting procedures for the VMStation enterprise monitoring and infrastructure services.

**WORKER_JOIN_FIX.md**
- Title: Worker Node Join Hanging Issue - Fix Documentation
- Summary: When running `./deploy.sh all --with-rke2 --yes`, the deployment would hang at:

**troubleshooting.md**
- Title: Troubleshooting Guide
- Summary: Quick diagnostic checks for VMStation clusters.

### Other Documentation

**AUTOSLEEP_RUNBOOK.md**
- Title: VMStation Auto-Sleep/Wake Operational Runbook
- Summary: This document provides operational procedures for managing the VMStation auto-sleep and wake functionality.

**BEST_PRACTICES.md**
- Title: VMStation Best Practices & Standards
- Summary: This document outlines the industry best practices, standards, and design principles applied to the VMStation automation.

**BLACKBOX_EXPORTER_DIAGNOSTICS.md**
- Title: Blackbox Exporter & Monitoring Stack Diagnostic Report
- Summary: **Blackbox Exporter**: Config parsing error - `timeout` field incorrectly nested within DNS prober section instead of at module level.

**DIAGNOSTIC_COMMANDS_EXPECTED_OUTPUT.md**
- Title: Diagnostic Commands & Expected Outputs - Post-Fix
- Summary: This document provides the exact diagnostic commands requested in the problem statement and their expected outputs after applying the fixes.

**ENTERPRISE_IMPLEMENTATION_SUMMARY.md**
- Title: Enterprise Monitoring and Infrastructure Enhancement - Implementation Summary
- Summary: This document summarizes the comprehensive enterprise-grade enhancements made to the VMStation Kubernetes cluster's monitoring and infrastructure serv...

**IMPLEMENTATION_SUMMARY.md**
- Title: Implementation Summary - CNI Plugin Fix and Infrastructure Planning
- Summary: October 8, 2025

**PROBLEM_STATEMENT_RESPONSE.md**
- Title: Complete Problem Statement Response
- Summary: **Date**: October 2025  

**REMOTE_IPMI_SETUP.md**
- Title: Remote IPMI Monitoring Setup Guide
- Summary: This guide explains how to configure and deploy remote IPMI monitoring for enterprise servers in the VMStation cluster.

**VALIDATION_IMPLEMENTATION_SUMMARY.md**
- Title: VMStation Sleep/Wake and Monitoring Validation Implementation Summary
- Summary: This implementation adds comprehensive automated validation for VMStation's auto-sleep/wake functionality and monitoring stack health, addressing all ...

**VALIDATION_TEST_GUIDE.md**
- Title: VMStation Auto-Sleep/Wake and Monitoring Validation Guide
- Summary: This document describes the comprehensive test suite for validating VMStation's auto-sleep/wake functionality and monitoring stack health.

**migration-risk-report.md**
- Title: VMStation Manifest Migration Risk Report
- Summary: This report identifies potential risks and ambiguities in the proposed manifest reorganization from `manifests/monitoring/` into platform-specific dir...


## Suggested Documentation Merges

These documents have overlapping content and could be consolidated:

**Deployment Runbooks**
- Files: DEPLOYMENT_RUNBOOK.md, DEPLOYMENT_FIXES_OCT2025.md, DEPLOYMENT_FIXES_OCT2025_PART2.md
- Suggestion: Merge into single comprehensive DEPLOYMENT_GUIDE.md with historical fixes in appendix

**Monitoring Stack Documentation**
- Files: MONITORING_STACK_FIXES_OCT2025.md, MONITORING_FIXES_README.md, MONITORING_FIX_SUMMARY.md
- Suggestion: Consolidate into MONITORING_CONFIGURATION.md with fixes timeline

**Loki Documentation**
- Files: LOKI_DRIFT_PREVENTION_IMPLEMENTATION.md, LOKI_ISSUES_RESOLUTION.md, LOKI_FIX_QUICK_REFERENCE.md, LOKI_CONFIG_DRIFT_PREVENTION.md
- Suggestion: Merge into LOKI_OPERATIONS_GUIDE.md

**Quick Start Guides**
- Files: QUICK_START.md, QUICK_START_FIXES.md, LOKI_CONFIG_QUICK_START.md, QUICK_REFERENCE_MONITORING_FIXES.md
- Suggestion: Consolidate into single QUICK_START_GUIDE.md


## Statistics

- Total documentation files: 49
- Root documentation: 3
- Deployment docs: 8
- Monitoring docs: 18
- Troubleshooting docs: 9
- Other docs: 11
