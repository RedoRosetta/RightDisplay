// Copyright © 2026 RedoRosetta
// First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
#ifndef RIGHTDISPLAY_AUDIO_BRIDGE_C_H
#define RIGHTDISPLAY_AUDIO_BRIDGE_C_H
#include <stdint.h>
#include "../../AudioVirtualDevice/SigningIdentity.h"
#ifdef __cplusplus
extern "C" {
#endif
// All functions except the actual IOProc are control-plane APIs. One serial owner.
typedef struct ABSession ABSession;
char *ABCopyDevicesJSON(void);
void ABFreeString(char *value);
ABSession *ABStartTest(const char *uid,const char *fixture,float gain,int muted,char **error);
char *ABPollJSON(ABSession *session);
void ABSetGain(ABSession *session,float gain,int muted);
// Invalidates before HAL teardown. Returns zero only for confirmed deregistration.
int ABStop(ABSession *session);
char *RVCopyStatusJSON(void);
#ifdef __cplusplus
}
#endif

#endif
