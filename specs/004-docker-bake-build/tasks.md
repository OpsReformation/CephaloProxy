# Tasks: Docker Build System Update

**Input**: Design documents from `/specs/004-docker-bake-build/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: No test tasks required - this is a build system configuration feature

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Review existing Dockerfile.distroless and verify it supports BuildKit ARGs
- [X] T002 [P] Verify Docker BuildKit is available on development machine
- [X] T003 [P] Review GitHub Actions workflow and identify build command locations

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create docker-bake.hcl configuration file with base target
- [X] T005 [P] Add ARG declarations to Dockerfile.distroless for platform detection (DISTROLESS_BASE, DISTROLESS_BASE_SHA, DEBIAN_VERSION, BUILDPLATFORM, TARGETPLATFORM)
- [X] T005a [US1] Verify Dockerfile.distroless supports building for different base images via ARG overrides
- [X] T006 Update GitHub Actions workflow to validate BuildKit availability before build
- [ ] T007 [P] Update README.md with Docker Bake build commands from quickstart.md
- [X] T008 [P] Verify docker-compose.production.yml can reference Docker Bake targets

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Multi-platform builds (Priority: P1) 🎯 MVP

**Goal**: Build Docker images for multiple platforms (amd64, arm64) from a single configuration

**Independent Test**: Run `docker buildx bake` and verify both linux/amd64 and linux/arm64 images are built successfully

### Implementation for User Story 1

- [X] T009 [US1] Configure cephaloproxy target in docker-bake.hcl to inherit from base and build for both platforms
- [X] T010 [US1] Add cache-from directive to cephaloproxy target for GitHub Actions cache
- [X] T011 [US1] Add cache-to directive to cephaloproxy target with max mode and zstd compression
- [X] T012 [US1] Configure tags for cephaloproxy target (cephaloproxy:latest, cephaloproxy:${VERSION})
- [X] T013 [US1] Update README.md to document multi-platform build command `docker buildx bake`
- [N/A] T014 [US1] ~~Verify single-platform build command `docker buildx bake amd64-only` works~~ — `amd64-only` target removed; per-platform builds driven by workflow matrix
- [N/A] T015 [US1] ~~Verify single-platform build command `docker buildx bake arm64-only` works~~ — `arm64-only` target removed; per-platform builds driven by workflow matrix

**Checkpoint**: At this point, User Story 1 should be fully functional - multi-platform builds work with caching

---

## Phase 4: User Story 2 - Improved build performance (Priority: P2)

**Goal**: Leverage Docker BuildKit's caching and parallel builds to reduce build times

**Independent Test**: Run `docker buildx bake dev` and verify local cache is used, then rebuild to confirm cache is hit

### Implementation for User Story 2

- [N/A] T016 [US2] ~~Configure dev target in docker-bake.hcl for local development with local cache~~ — `dev` target removed; `image` target with BuildKit internal cache is sufficient
- [N/A] T017 [US2] ~~Add local cache source (type=local,src=/tmp/docker-build-cache) to dev target~~ — superseded
- [N/A] T018 [US2] ~~Add local cache destination (type=local,dest=/tmp/docker-build-cache-new) to dev target~~ — superseded
- [X] T019 [US2] Update README.md to document development build command `docker buildx bake`
- [X] T020 [US2] Add build-time validation script to check BuildKit availability (check for BUILDKIT_DISABLE and buildx version)
- [X] T021 [US2] Update GitHub Actions workflow to use `docker buildx bake` command instead of `docker build`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - multi-platform builds with caching and development builds

---

## Phase 5: User Story 3 - Simplified multi-platform builds (Priority: P3)

**Goal**: Build Docker images for different platforms with a single command

**Independent Test**: Run `docker buildx bake amd64-only` and `docker buildx bake arm64-only` separately and verify each builds the correct platform

### Implementation for User Story 3

- [N/A] T022 [US3] ~~Configure amd64-only target~~ — removed; platform selection via workflow matrix `set` overrides
- [N/A] T023 [US3] ~~Configure arm64-only target~~ — removed; platform selection via workflow matrix `set` overrides
- [N/A] T024 [US3] ~~Add tags for amd64-only target~~ — superseded by digest-based pipeline; tags applied at merge step
- [N/A] T025 [US3] ~~Add tags for arm64-only target~~ — superseded by digest-based pipeline; tags applied at merge step
- [N/A] T026 [US3] ~~Add cache-from to amd64-only~~ — cache configured via workflow `set` inputs
- [N/A] T027 [US3] ~~Add cache-from to arm64-only~~ — cache configured via workflow `set` inputs
- [N/A] T028 [US3] ~~Add cache-to to amd64-only~~ — cache configured via workflow `set` inputs
- [N/A] T029 [US3] ~~Add cache-to to arm64-only~~ — cache configured via workflow `set` inputs
- [N/A] T043 [US3] ~~Create single-platform group~~ — removed; CI uses workflow matrix, not bake groups
- [X] T044 [US3] Update README.md to document build commands

**Checkpoint**: All user stories should now be independently functional - complete Docker Bake system

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T030 [P] Add build-time validation script to verify BuildKit availability with clear error message
- [X] T031 [P] Update CLAUDE.md with new Active Technologies (Docker BuildKit, Docker Bake, Docker Compose)
- [X] T032 [P] Document cache backend requirements (GitHub Actions cache and local cache) in README.md
- [X] T043 [P] **TEST**: Validate HCL syntax of docker-bake.hcl using `docker buildx bake --print`
- [ ] T044 [P] **TEST**: Verify cache functionality - run build, rebuild to confirm cache hit, document cache hit rate
- [ ] T045 [P] **TEST**: Verify multi-platform build creates both linux/amd64 and linux/arm64 images
- [ ] T046 [P] **TEST**: Verify BuildKit configuration is properly enabled and validated
- [X] T033 [P] Verify all Dockerfile ARGs are properly referenced in docker-bake.hcl
- [X] T034 [P] Validate docker-bake.hcl syntax using `docker buildx bake --print`
- [ ] T035 [P] Run quickstart.md verification steps to ensure all commands work as documented
- [ ] T036 [P] Test override base image version command `docker buildx bake --var DISTROLESS_BASE=... --var DEBIAN_VERSION=...`
- [X] T037 [P] Test dry run command `docker buildx bake --print` to verify configuration
- [ ] T038 [P] Test progress output command `docker buildx bake --progress=plain` for detailed logs
- [X] T039 [P] Verify docker-compose.production.yml can reference build targets correctly
- [ ] T040 [P] Add deprecation warnings to docker-compose.production.yml build commands
- [X] T041 [P] Verify no direct `docker build` commands remain in CI/CD workflows
- [ ] T042 [P] Verify container labels match expected format from existing builds

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 cache configuration but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Extends US1/US2 targets but independently testable

### Within Each User Story

- Configure targets in docker-bake.hcl before testing
- Update documentation after implementation
- Verify single-platform target builds work before multi-platform
- Test cache functionality after basic build works

### Parallel Opportunities

- All Setup tasks (T001, T002, T003) can run in parallel
- All Foundational tasks marked [P] (T005, T007, T008) can run in parallel
- Phase 3 tasks marked [P] (T009, T013, T014, T015) can run in parallel
- Phase 4 tasks marked [P] (T019, T020, T021) can run in parallel
- Phase 5 tasks marked [P] (T022, T024, T025, T028, T029) can run in parallel
- Phase 6 tasks marked [P] (T043, T044, T032, T033, T034, T035, T036, T037, T038, T039) can run in parallel
- Test tasks (T043-T046) can run in parallel as they validate different aspects of the build system
- Different user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 1

```bash
# Configure targets together (sequential - need docker-bake.hcl):
Task: "Configure cephaloproxy target in docker-bake.hcl"
Task: "Add cache-from directive to cephaloproxy target"
Task: "Add cache-to directive to cephaloproxy target"
Task: "Configure tags for cephaloproxy target"

# Documentation updates in parallel:
Task: "Update README.md to document multi-platform build command"
Task: "Verify single-platform build command works"
Task: "Verify single-platform build command works"
```

---

## Parallel Example: User Story 2

```bash
# Configure dev target and update docs in parallel:
Task: "Configure dev target in docker-bake.hcl for local development"
Task: "Update README.md to document development build command"

# CI/CD updates (can run in parallel):
Task: "Add build-time validation script to check BuildKit availability"
Task: "Update GitHub Actions workflow to use docker buildx bake command"
```

---

## Parallel Example: User Story 3

```bash
# Configure platform-specific targets in parallel:
Task: "Configure amd64-only target in docker-bake.hcl"
Task: "Configure arm64-only target in docker-bake.hcl"
Task: "Add tags for amd64-only target"
Task: "Add tags for arm64-only target"

# Documentation updates in parallel:
Task: "Create single-platform group in docker-bake.hcl"
Task: "Update README.md to document single-platform build commands"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T008) - CRITICAL
3. Complete Phase 3: User Story 1 (T009-T015)
4. **STOP and VALIDATE**: Test multi-platform build independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Build system configuration features may use validation scripts instead of formal tests
- Build validation should include: syntax validation, cache functionality verification, multi-platform build testing
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- Dockerfile.distroless adaptations should be minimal (only ARG additions)
- CI/CD targets use GitHub Actions cache (gha backend) for cache persistence
- Local dev target uses local filesystem cache (local backend)
- All targets should inherit from base target for consistency
