/**
 * Navbot Stuckbot Visualiser v2.20
 * Caches stuck bot locations for the current map on map start, spawns floating sprite markers,
 * and prints locations in simplified console format.
 */

#include <sourcemod>
#include <sdktools>

public Plugin:myinfo =
{
    name = "Navbot Stuckbot Visualiser",
    author = "Claude.ai guided by DNA.styx",
    description = "Displays stuck bot locations for the current map with sprite markers",
    version = "2.20",
    url = "https://github.com/DNA-styx/Navbot-StuckBot-Visualiser"
};

#define MAX_STUCK_BOTS 256

float g_StuckX[MAX_STUCK_BOTS];
float g_StuckY[MAX_STUCK_BOTS];
float g_StuckZ[MAX_STUCK_BOTS];
int   g_StuckCount = 0;

int g_SpriteEntities[MAX_STUCK_BOTS];

char g_SpriteModel[64];
char g_RenderMode[4];
char g_RenderAmt[4];      // empty string = do not set this keyvalue (use engine default)
char g_GlowProxySize[8];  // empty string = do not set this keyvalue (use engine default)
char g_Scale[8];

public void OnPluginStart()
{
    char gameFolder[32];
    GetGameFolderName(gameFolder, sizeof(gameFolder));

    if (StrEqual(gameFolder, "dod", false))
    {
        // DoD:S - last confirmed-working config (predates the ZPS rendering work below).
        strcopy(g_SpriteModel, sizeof(g_SpriteModel), "sprites/glow01.vmt");
        strcopy(g_RenderMode, sizeof(g_RenderMode), "5"); // kRenderTransAdd
        g_RenderAmt[0] = '\0';
        g_GlowProxySize[0] = '\0';
        strcopy(g_Scale, sizeof(g_Scale), "0.5");
    }
    else if (StrEqual(gameFolder, "zps", false))
    {
        // ZPS - confirmed working through live testing.
        strcopy(g_SpriteModel, sizeof(g_SpriteModel), "sprites/glow03.spr");
        strcopy(g_RenderMode, sizeof(g_RenderMode), "9"); // kRenderWorldGlow
        strcopy(g_RenderAmt, sizeof(g_RenderAmt), "255");
        strcopy(g_GlowProxySize, sizeof(g_GlowProxySize), "1");
        strcopy(g_Scale, sizeof(g_Scale), "4");
    }
    else
    {
        // Unrecognised game - fall back to the DoD:S config and flag it for review.
        strcopy(g_SpriteModel, sizeof(g_SpriteModel), "sprites/glow01.vmt");
        strcopy(g_RenderMode, sizeof(g_RenderMode), "5");
        g_RenderAmt[0] = '\0';
        g_GlowProxySize[0] = '\0';
        strcopy(g_Scale, sizeof(g_Scale), "0.5");
        PrintToServer("[Navbot Stuckbot Visualiser] Game folder '%s' not in known list, using DoD:S sprite config. Verify it renders.", gameFolder);
    }

    PrintToServer("[Navbot Stuckbot Visualiser] Detected game '%s', using sprite model '%s'.", gameFolder, g_SpriteModel);
}

public void OnMapStart()
{
    g_StuckCount = 0;

    PrintToServer("[Navbot Stuckbot Visualiser] Map started, loading stuck bot locations...");

    int spriteIndex = PrecacheModel(g_SpriteModel, true);
    PrintToServer("[Navbot Stuckbot Visualiser] Precached sprite model '%s' (index %d).", g_SpriteModel, spriteIndex);

    char map[64];
    GetCurrentMap(map, sizeof(map));

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/navbot-stuckbot-visualiser/locations.txt");

    if (!FileExists(path))
    {
        PrintToServer("[Navbot Stuckbot Visualiser] File not found: %s", path);
        return;
    }

    Handle kv = CreateKeyValues("StuckBots");
    FileToKeyValues(kv, path);

    if (!KvGotoFirstSubKey(kv))
    {
        PrintToServer("[Navbot Stuckbot Visualiser] No stuck bot entries found.");
        CloseHandle(kv);
        return;
    }

    do
    {
        if (g_StuckCount >= MAX_STUCK_BOTS)
        {
            PrintToServer("[Navbot Stuckbot Visualiser] Maximum stuck bot limit reached.");
            break;
        }

        char botMap[64];
        KvGetString(kv, "map", botMap, sizeof(botMap));

        if (StrEqual(botMap, map))
        {
            g_StuckX[g_StuckCount] = KvGetFloat(kv, "x", 0.0);
            g_StuckY[g_StuckCount] = KvGetFloat(kv, "y", 0.0);
            g_StuckZ[g_StuckCount] = KvGetFloat(kv, "z", 0.0);

            g_StuckCount++;
        }
    }
    while (KvGotoNextKey(kv));

    CloseHandle(kv);

    // Print cached data in simplified format
    PrintToServer("[Navbot Stuckbot Visualiser] Stuck bots for map %s:", map);
    for (int i = 0; i < g_StuckCount; i++)
    {
        PrintToServer("  Location %d: %f %f %f", i+1, g_StuckX[i], g_StuckY[i], g_StuckZ[i]);
    }
    PrintToServer("[Navbot Stuckbot Visualiser] Total stuck bots for map %s: %d", map, g_StuckCount);

    SpawnSprites();
}

void SpawnSprites()
{
    for (int i = 0; i < g_StuckCount; i++)
    {
        float vec[3];
        vec[0] = g_StuckX[i];
        vec[1] = g_StuckY[i];
        vec[2] = g_StuckZ[i] + 16.0; // slightly above the ground

        g_SpriteEntities[i] = CreateEntityByName("env_sprite");
        if (g_SpriteEntities[i] != -1)
        {
            DispatchKeyValue(g_SpriteEntities[i], "model", g_SpriteModel);
            DispatchKeyValue(g_SpriteEntities[i], "rendermode", g_RenderMode);
            DispatchKeyValue(g_SpriteEntities[i], "renderfx", "0");
            DispatchKeyValue(g_SpriteEntities[i], "rendercolor", "255 0 0"); // red

            if (g_RenderAmt[0] != '\0')
            {
                DispatchKeyValue(g_SpriteEntities[i], "renderamt", g_RenderAmt);
            }
            if (g_GlowProxySize[0] != '\0')
            {
                DispatchKeyValue(g_SpriteEntities[i], "GlowProxySize", g_GlowProxySize);
            }

            DispatchKeyValue(g_SpriteEntities[i], "scale", g_Scale);
            DispatchKeyValue(g_SpriteEntities[i], "spawnflags", "1"); // Start On

            TeleportEntity(g_SpriteEntities[i], vec, NULL_VECTOR, NULL_VECTOR);
            DispatchSpawn(g_SpriteEntities[i]);
            ActivateEntity(g_SpriteEntities[i]);
            AcceptEntityInput(g_SpriteEntities[i], "ShowSprite");
        }
    }

    PrintToServer("[Navbot Stuckbot Visualiser] Spawned %d sprite markers.", g_StuckCount);
}

public void OnMapEnd()
{
    KillAllSprites();
}

public void OnPluginEnd()
{
    // Without this, sprites spawned by this plugin were left orphaned on screen
    // when the plugin was unloaded, since only OnMapEnd cleaned them up before.
    KillAllSprites();
}

void KillAllSprites()
{
    for (int i = 0; i < g_StuckCount; i++)
    {
        if (IsValidEntity(g_SpriteEntities[i]))
        {
            AcceptEntityInput(g_SpriteEntities[i], "Kill");
        }
        g_SpriteEntities[i] = -1;
    }
}
