/**
 * Navbot Stuckbot Visualiser v2.25
 * Caches stuck bot locations for the current map, provides an in-game menu for
 * toggling sprite markers on/off, and lists all maps with data in locations.txt.
 */

#include <sourcemod>
#include <sdktools>

public Plugin:myinfo =
{
    name = "Navbot Stuckbot Visualiser",
    author = "Claude.ai guided by DNA.styx",
    description = "Caches and displays stuck bot locations for the current map with sprite markers",
    version = "2.25",
    url = "https://github.com/DNA-styx/Navbot-StuckBot-Visualiser"
};

#define MAX_STUCK_BOTS 256

// Current map sprite data
float g_StuckX[MAX_STUCK_BOTS];
float g_StuckY[MAX_STUCK_BOTS];
float g_StuckZ[MAX_STUCK_BOTS];
int   g_StuckCount = 0;

int  g_SpriteEntities[MAX_STUCK_BOTS];
bool g_SpritesVisible = false;

// All maps present in locations.txt (built on each map load)
ArrayList g_MapNames;
ArrayList g_MapCounts;

char g_CurrentMap[64];
char g_SelectedMap[64]; // holds map name during changelevel confirmation

// Per-game sprite config
char g_SpriteModel[64];
char g_RenderMode[4];
char g_RenderAmt[4];     // empty string = do not set (use engine default)
char g_GlowProxySize[8]; // empty string = do not set (use engine default)
char g_Scale[8];

// ─── Setup ────────────────────────────────────────────────────────────────────

public void OnPluginStart()
{
    g_MapNames  = new ArrayList(ByteCountToCells(64));
    g_MapCounts = new ArrayList();

    char gameFolder[32];
    GetGameFolderName(gameFolder, sizeof(gameFolder));

    if (StrEqual(gameFolder, "dod", false))
    {
        // DoD:S - last confirmed-working config (predates the ZPS rendering work below).
        strcopy(g_SpriteModel, sizeof(g_SpriteModel), "sprites/glow01.vmt");
        strcopy(g_RenderMode, sizeof(g_RenderMode), "5"); // kRenderTransAdd
        g_RenderAmt[0]      = '\0';
        g_GlowProxySize[0]  = '\0';
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
        // Unrecognised game - fall back to DoD:S config and flag it for review.
        strcopy(g_SpriteModel, sizeof(g_SpriteModel), "sprites/glow01.vmt");
        strcopy(g_RenderMode, sizeof(g_RenderMode), "5");
        g_RenderAmt[0]      = '\0';
        g_GlowProxySize[0]  = '\0';
        strcopy(g_Scale, sizeof(g_Scale), "0.5");
        PrintToServer("[Navbot Stuckbot Visualiser] Game folder '%s' not in known list, using DoD:S sprite config. Verify it renders.", gameFolder);
    }

    PrintToServer("[Navbot Stuckbot Visualiser] Detected game '%s', using sprite model '%s'.", gameFolder, g_SpriteModel);

    RegAdminCmd("sm_stuckbots", Cmd_StuckBots, ADMFLAG_ROOT, "Open Stuckbot Visualiser menu");
}

public void OnMapStart()
{
    g_StuckCount     = 0;
    g_SpritesVisible = false;
    g_MapNames.Clear();
    g_MapCounts.Clear();

    GetCurrentMap(g_CurrentMap, sizeof(g_CurrentMap));

    int spriteIndex = PrecacheModel(g_SpriteModel, true);
    PrintToServer("[Navbot Stuckbot Visualiser] Map started. Precached '%s' (index %d).", g_SpriteModel, spriteIndex);

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
        PrintToServer("[Navbot Stuckbot Visualiser] No entries found in locations.txt.");
        CloseHandle(kv);
        return;
    }

    do
    {
        char botMap[64];
        KvGetString(kv, "map", botMap, sizeof(botMap));

        // Track all unique maps and their location counts
        int mapIdx = g_MapNames.FindString(botMap);
        if (mapIdx == -1)
        {
            g_MapNames.PushString(botMap);
            g_MapCounts.Push(1);
        }
        else
        {
            g_MapCounts.Set(mapIdx, g_MapCounts.Get(mapIdx) + 1);
        }

        // Store coordinates for the current map
        if (StrEqual(botMap, g_CurrentMap) && g_StuckCount < MAX_STUCK_BOTS)
        {
            g_StuckX[g_StuckCount] = KvGetFloat(kv, "x", 0.0);
            g_StuckY[g_StuckCount] = KvGetFloat(kv, "y", 0.0);
            g_StuckZ[g_StuckCount] = KvGetFloat(kv, "z", 0.0);
            g_StuckCount++;
        }
    }
    while (KvGotoNextKey(kv));

    CloseHandle(kv);

    PrintToServer("[Navbot Stuckbot Visualiser] Loaded %d map(s) from locations.txt. Current map '%s' has %d stuck location(s).",
        g_MapNames.Length, g_CurrentMap, g_StuckCount);
}

// ─── Auto-show menu for root admins ──────────────────────────────────────────

public void OnClientPutInServer(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    if (!CheckCommandAccess(client, "sm_stuckbots", ADMFLAG_ROOT, true))
        return;

    int userId = GetClientUserId(client);
    CreateTimer(3.0, Timer_AutoShowMenu, userId, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_AutoShowMenu(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Stop;

    ShowMapListMenu(client);
    return Plugin_Stop;
}

// ─── Admin command ────────────────────────────────────────────────────────────

public Action Cmd_StuckBots(int client, int args)
{
    if (client == 0)
        return Plugin_Handled;

    ShowMapListMenu(client);
    return Plugin_Handled;
}

// ─── Map list menu ────────────────────────────────────────────────────────────

void ShowMapListMenu(int client)
{
    Menu menu = new Menu(MenuHandler_MapList);

    char displayMap[64];
    GetMapDisplayName(g_CurrentMap, displayMap, sizeof(displayMap));
    menu.SetTitle("[StuckBot Visualiser]\n%s\n ", displayMap);
    menu.ExitButton = true;

    if (g_MapNames.Length == 0)
    {
        menu.AddItem("", "No data in locations.txt", ITEMDRAW_DISABLED);
    }
    else
    {
        for (int i = 0; i < g_MapNames.Length; i++)
        {
            char mapName[64];
            g_MapNames.GetString(i, mapName, sizeof(mapName));
            int count = g_MapCounts.Get(i);

            char mapDisplay[64];
            GetMapDisplayName(mapName, mapDisplay, sizeof(mapDisplay));

            char entry[128];
            if (StrEqual(mapName, g_CurrentMap, false))
                Format(entry, sizeof(entry), "[current] %s - %d pts", mapDisplay, count);
            else
                Format(entry, sizeof(entry), "%s - %d pts", mapDisplay, count);

            menu.AddItem(mapName, entry);
        }
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MapList(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char mapName[64];
        menu.GetItem(param2, mapName, sizeof(mapName));

        if (StrEqual(mapName, g_CurrentMap, false))
            ShowToggleMenu(param1);
        else
        {
            strcopy(g_SelectedMap, sizeof(g_SelectedMap), mapName);
            ShowChangeLevelMenu(param1);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        // Reshow unless the player deliberately pressed Exit or has disconnected
        if (param2 != MenuCancel_Exit && IsClientInGame(param1))
            ShowMapListMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

// ─── Toggle menu (current map) ────────────────────────────────────────────────

void ShowToggleMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Toggle);

    char displayMap[64];
    GetMapDisplayName(g_CurrentMap, displayMap, sizeof(displayMap));
    menu.SetTitle("[StuckBot Visualiser]\n%s\n ", displayMap);
    menu.ExitButton = true;

    char toggleLabel[64];
    if (g_SpritesVisible)
        Format(toggleLabel, sizeof(toggleLabel), "Hide Sprites (%d locations)", g_StuckCount);
    else
        Format(toggleLabel, sizeof(toggleLabel), "Show Sprites (%d locations)", g_StuckCount);

    menu.AddItem("toggle", toggleLabel);
    menu.AddItem("back",   "Back");

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Toggle(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "toggle"))
        {
            if (g_SpritesVisible)
            {
                KillAllSprites();
                g_SpritesVisible = false;
            }
            else
            {
                SpawnSprites();
                g_SpritesVisible = true;
            }
            ShowToggleMenu(param1);
        }
        else if (StrEqual(info, "back"))
        {
            ShowMapListMenu(param1);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 != MenuCancel_Exit && IsClientInGame(param1))
            ShowToggleMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

// ─── Changelevel confirmation menu ────────────────────────────────────────────

void ShowChangeLevelMenu(int client)
{
    Menu menu = new Menu(MenuHandler_ChangeLevel);

    char displayMap[64];
    GetMapDisplayName(g_SelectedMap, displayMap, sizeof(displayMap));
    menu.SetTitle("[StuckBot Visualiser]\nChangelevel to:\n%s\n ", displayMap);
    menu.ExitButton = true;

    menu.AddItem("yes",  "Yes - changelevel");
    menu.AddItem("back", "Back");

    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ChangeLevel(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(param2, info, sizeof(info));

        if (StrEqual(info, "yes"))
        {
            char cmd[128];
            Format(cmd, sizeof(cmd), "changelevel %s", g_SelectedMap);
            ServerCommand(cmd);
        }
        else if (StrEqual(info, "back"))
        {
            ShowMapListMenu(param1);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 != MenuCancel_Exit && IsClientInGame(param1))
            ShowChangeLevelMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

// ─── Sprite management ────────────────────────────────────────────────────────

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
            DispatchKeyValue(g_SpriteEntities[i], "model",       g_SpriteModel);
            DispatchKeyValue(g_SpriteEntities[i], "rendermode",  g_RenderMode);
            DispatchKeyValue(g_SpriteEntities[i], "renderfx",    "0");
            DispatchKeyValue(g_SpriteEntities[i], "rendercolor", "255 0 0"); // red

            if (g_RenderAmt[0] != '\0')
                DispatchKeyValue(g_SpriteEntities[i], "renderamt",     g_RenderAmt);
            if (g_GlowProxySize[0] != '\0')
                DispatchKeyValue(g_SpriteEntities[i], "GlowProxySize", g_GlowProxySize);

            DispatchKeyValue(g_SpriteEntities[i], "scale",       g_Scale);
            DispatchKeyValue(g_SpriteEntities[i], "spawnflags",  "1"); // Start On

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
    g_SpritesVisible = false;
}

public void OnPluginEnd()
{
    // Without this, sprites are left orphaned on screen when the plugin is unloaded.
    KillAllSprites();
}

void KillAllSprites()
{
    for (int i = 0; i < g_StuckCount; i++)
    {
        if (IsValidEntity(g_SpriteEntities[i]))
            AcceptEntityInput(g_SpriteEntities[i], "Kill");
        g_SpriteEntities[i] = -1;
    }
}
