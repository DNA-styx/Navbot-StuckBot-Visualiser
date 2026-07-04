/**
 * Navbot Stuckbot Visualiser v2.27
 * Caches stuck bot locations for the current map, provides an in-game menu for
 * toggling sprite markers on/off, and lists all maps with data in the logs directory.
 */

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name = "Navbot Stuckbot Visualiser",
    author = "Claude.ai guided by DNA.styx",
    description = "Displays sprite markers at stuck bot locations",
    version = "3.00",
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

// All maps found in the logs directory (built on each map load)
ArrayList g_MapNames;

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
    g_MapNames = new ArrayList(ByteCountToCells(64));

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

    GetCurrentMap(g_CurrentMap, sizeof(g_CurrentMap));

    int spriteIndex = PrecacheModel(g_SpriteModel, true);
    PrintToServer("[Navbot Stuckbot Visualiser] Map started. Precached '%s' (index %d).", g_SpriteModel, spriteIndex);

    ScanLogFiles();

    PrintToServer("[Navbot Stuckbot Visualiser] Found %d map(s) in logs. Current map '%s' has %d stuck location(s).",
        g_MapNames.Length, g_CurrentMap, g_StuckCount);
}

// ─── Log file scanning and parsing ───────────────────────────────────────────

// Returns true and extracts mapName and dateStr from a filename of the form
// stucklog_MAPNAME_YYYYMMDD.log. Date is 8 digits (YYYYMMDD).
bool ExtractMapAndDate(const char[] filename, char[] mapOut, int mapSize, char[] dateOut, int dateSize)
{
    // Must start with "stucklog_"
    if (strncmp(filename, "stucklog_", 9) != 0)
        return false;

    // Must end with ".log"
    int fnLen = strlen(filename);
    if (fnLen < 14 || !StrEqual(filename[fnLen - 4], ".log"))
        return false;

    // Strip prefix and suffix: work = MAPNAME_YYYYMMDD
    char work[256];
    strcopy(work, sizeof(work), filename[9]);
    int workLen = strlen(work) - 4;
    work[workLen] = '\0'; // remove ".log"

    // Last 8 chars must be digits (YYYYMMDD), preceded by '_'
    if (workLen < 10)
        return false;

    if (work[workLen - 9] != '_')
        return false;

    for (int i = workLen - 8; i < workLen; i++)
    {
        if (work[i] < '0' || work[i] > '9')
            return false;
    }

    // Extract date and map name
    strcopy(dateOut, dateSize, work[workLen - 8]);
    work[workLen - 9] = '\0';
    strcopy(mapOut, mapSize, work);

    return true;
}

void ParseLogFile(const char[] filepath)
{
    File f = OpenFile(filepath, "r");
    if (f == null)
    {
        PrintToServer("[Navbot Stuckbot Visualiser] Could not open log file: %s", filepath);
        return;
    }

    char line[512];
    while (f.ReadLine(line, sizeof(line)))
    {
        // Find " at <" — coordinates follow immediately after the opening <
        int atPos = StrContains(line, " at <");
        if (atPos == -1)
            continue;

        int startPos = atPos + 5; // skip " at <"
        int endOffset = StrContains(line[startPos], ">");
        if (endOffset == -1)
            continue;

        char coords[64];
        strcopy(coords, sizeof(coords), line[startPos]);
        coords[endOffset] = '\0';

        // coords is now "X Y Z"
        char parts[3][32];
        if (ExplodeString(coords, " ", parts, 3, 32) < 3)
            continue;

        if (g_StuckCount >= MAX_STUCK_BOTS)
        {
            PrintToServer("[Navbot Stuckbot Visualiser] Maximum stuck bot limit (%d) reached.", MAX_STUCK_BOTS);
            break;
        }

        g_StuckX[g_StuckCount] = StringToFloat(parts[0]);
        g_StuckY[g_StuckCount] = StringToFloat(parts[1]);
        g_StuckZ[g_StuckCount] = StringToFloat(parts[2]);
        g_StuckCount++;
    }

    delete f;
}

void ScanLogFiles()
{
    char logsDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, logsDir, sizeof(logsDir), "logs");

    DirectoryListing dir = OpenDirectory(logsDir);
    if (dir == null)
    {
        PrintToServer("[Navbot Stuckbot Visualiser] Could not open logs directory: %s", logsDir);
        return;
    }

    char bestFile[PLATFORM_MAX_PATH]; // most recent log file for current map
    char bestDate[16];                // YYYYMMDD of the best file found so far
    bestFile[0] = '\0';
    bestDate[0] = '\0';

    char filename[256];
    FileType ft;

    while (dir.GetNext(filename, sizeof(filename), ft))
    {
        if (ft != FileType_File)
            continue;

        char mapName[64];
        char dateStr[16];
        if (!ExtractMapAndDate(filename, mapName, sizeof(mapName), dateStr, sizeof(dateStr)))
            continue;

        // Add to the map list if not already present
        if (g_MapNames.FindString(mapName) == -1)
            g_MapNames.PushString(mapName);

        // Track the most recent file for the current map
        if (StrEqual(mapName, g_CurrentMap, false))
        {
            if (strcmp(dateStr, bestDate) > 0)
            {
                strcopy(bestDate, sizeof(bestDate), dateStr);
                Format(bestFile, sizeof(bestFile), "%s/%s", logsDir, filename);
            }
        }
    }

    delete dir;

    if (bestFile[0] != '\0')
    {
        PrintToServer("[Navbot Stuckbot Visualiser] Parsing log file: %s", bestFile);
        ParseLogFile(bestFile);
    }
    else
    {
        PrintToServer("[Navbot Stuckbot Visualiser] No log file found for current map '%s'.", g_CurrentMap);
    }
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
        menu.AddItem("", "No stucklog files found", ITEMDRAW_DISABLED);
    }
    else
    {
        for (int i = 0; i < g_MapNames.Length; i++)
        {
            char mapName[64];
            g_MapNames.GetString(i, mapName, sizeof(mapName));

            char mapDisplay[64];
            GetMapDisplayName(mapName, mapDisplay, sizeof(mapDisplay));

            char entry[128];
            if (StrEqual(mapName, g_CurrentMap, false))
                Format(entry, sizeof(entry), "[current] %s - %d pts", mapDisplay, g_StuckCount);
            else
                Format(entry, sizeof(entry), "%s", mapDisplay);

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
        // No reshow here: Interrupt fires whenever a different menu is opened
        // from this menu's Select handler. Exit/Disconnect need no action.
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

// ─── Toggle menu (current map) ────────────────────────────────────────────────

void ShowToggleMenuDeferred(int client)
{
    int userId = GetClientUserId(client);
    CreateTimer(0.1, Timer_ShowToggleMenu, userId, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ShowToggleMenu(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    if (client != 0 && IsClientInGame(client))
        ShowToggleMenu(client);
    return Plugin_Stop;
}

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
            ShowToggleMenuDeferred(param1);
        }
        else if (StrEqual(info, "back"))
        {
            ShowMapListMenu(param1);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        // No reshow here: the deferred timer handles redisplay after toggle.
        // "Back" opens a different menu directly, firing Interrupt here.
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
        // No reshow here: "Back" opens the map list directly.
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
