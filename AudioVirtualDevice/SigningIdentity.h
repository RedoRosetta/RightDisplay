// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#ifndef RD_SIGNING_IDENTITY_H
#define RD_SIGNING_IDENTITY_H
// Build-time selection only. Official default is preserved; supply one team to all components.
#ifndef RD_SIGNING_TEAM
#define RD_SIGNING_TEAM "45F25M3DS7"
#endif
static inline const char *RDComponentSigningTeam(void) { return RD_SIGNING_TEAM; }
#define RD_STRINGIFY_INNER(x) #x
#define RD_STRINGIFY(x) RD_STRINGIFY_INNER(x)
#if defined(RD_ADHOC_BROKER_CDHASH) && defined(RD_ADHOC_DRIVER_CDHASH)
// Explicit release-content pins, NOT a publisher/Team identity. No mutable runtime allowlist.
#define RD_BROKER_REQUIREMENT "identifier \"com.rightdisplay.audio.Transport\" and cdhash H\"" RD_STRINGIFY(RD_ADHOC_BROKER_CDHASH) "\""
#define RD_DRIVER_REQUIREMENT "identifier \"com.rightdisplay.audio.VirtualVolume\" and cdhash H\"" RD_STRINGIFY(RD_ADHOC_DRIVER_CDHASH) "\""
#elif defined(RD_ADHOC_BROKER_CDHASH)
// Driver is built after Broker, before its own hash exists.
#define RD_BROKER_REQUIREMENT "identifier \"com.rightdisplay.audio.Transport\" and cdhash H\"" RD_STRINGIFY(RD_ADHOC_BROKER_CDHASH) "\""
#define RD_DRIVER_REQUIREMENT "anchor apple generic and identifier \"com.rightdisplay.audio.VirtualVolume\" and certificate leaf[subject.OU] = \"" RD_SIGNING_TEAM "\""
#else
#define RD_BROKER_REQUIREMENT "anchor apple generic and identifier \"com.rightdisplay.audio.Transport\" and certificate leaf[subject.OU] = \"" RD_SIGNING_TEAM "\""
#define RD_DRIVER_REQUIREMENT "anchor apple generic and identifier \"com.rightdisplay.audio.VirtualVolume\" and certificate leaf[subject.OU] = \"" RD_SIGNING_TEAM "\""
#endif
static inline const char *RDDriverRequirement(void) { return RD_DRIVER_REQUIREMENT; }
#endif
