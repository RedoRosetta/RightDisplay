// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#ifndef RD_SIGNING_IDENTITY_H
#define RD_SIGNING_IDENTITY_H
// Build-time selection only. Official default is preserved; supply one team to all components.
#ifndef RD_SIGNING_TEAM
#define RD_SIGNING_TEAM "45F25M3DS7"
#endif
static inline const char *RDComponentSigningTeam(void) { return RD_SIGNING_TEAM; }
#define RD_BROKER_REQUIREMENT "anchor apple generic and identifier \"com.rightdisplay.audio.Transport\" and certificate leaf[subject.OU] = \"" RD_SIGNING_TEAM "\""
#endif
