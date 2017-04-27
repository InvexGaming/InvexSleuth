/**
* InvexSleuth
* Plugin is heavily based on the SourceBans++ SourceSleuth plugin
*/

#include <sourcemod>
#include <sourcebans>
#include "convertsteamid.inc"

#pragma semicolon 1
#pragma newdecls required

//Defines
#define VERSION "1.01"
#define CHECK_DELAY 30.0
#define SQL_SB_QUERY_SIZE 16384

//ConVars
ConVar g_cvar_sbprefix = null;
ConVar g_cvar_banlengthmodifier = null;

//Handles
Handle hSBDatabase = null;
Handle hIdentityLoggerDatabase = null;

//Bools
bool CanUseSourcebans = false;

public Plugin myinfo =
{
  name = "InvexSleuth",
  author = "Invex | Byte",
  description = "Plugin will check for banned identities and ban the player.",
  version = VERSION,
  url = "http://www.invexgaming.com.au"
};

public void OnPluginStart()
{
  //Flags
  CreateConVar("sm_invexsleuth_version", VERSION, "", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
  
  //ConVars
  g_cvar_sbprefix = CreateConVar("sm_invexsleuth_prefix", "sb", "Prexfix for sourcebans tables: Default sb");
  g_cvar_banlengthmodifier = CreateConVar("sm_invexsleuth_banlengthmodifier", "2.0", "Multiplier for ban length upon banning: Default 2.0");
  
  AutoExecConfig(true, "invexsleuth");
  
  //SQL
  SQL_TConnect(SQL_OnConnectSB, "sourcebans");
  SQL_TConnect(SQL_OnConnectIdentityLogger, "identitylogger");
}

public void OnAllPluginsLoaded()
{
  CanUseSourcebans = LibraryExists("sourcebans");
}

public void OnLibraryAdded(const char[] name)
{
  if (StrEqual("sourcebans", name))
    CanUseSourcebans = true;
}

public void OnLibraryRemoved(const char[] name)
{
  if (StrEqual("sourcebans", name))
    CanUseSourcebans = false;
}

public void SQL_OnConnectSB(Handle owner, Handle hndl, const char[] error, any data)
{
  if (hndl == null)
    LogError("InvexSleuth: SourceBans Database connection error: %s", error);
  else
    hSBDatabase = hndl;
}

public void SQL_OnConnectIdentityLogger(Handle owner, Handle hndl, const char[] error, any data)
{
  if (hndl == null)
    LogError("InvexSleuth: IdentityLogger Database connection error: %s", error);
  else
    hIdentityLoggerDatabase = hndl;
}

public void OnClientPostAdminCheck(int client)
{
  //Perform checks with a sufficient delay
  CreateTimer(CHECK_DELAY, PerformClientCheck, client);
}

public Action PerformClientCheck(Handle timer, int client)
{
  if (!CanUseSourcebans)
    return;
    
  //Check client
  if (!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
    return;
    
  if (!IsClientAuthorized(client)) {
    //We need to delay slightly
    CreateTimer(5.0, PerformClientCheck, client);
    return;
  }
    
  //Check database connections
  if (hSBDatabase == null) {
    SQL_TConnect(SQL_OnConnectSB, "sourcebans");
    CreateTimer(5.0, PerformClientCheck, client);
    return;
  }
  
  if (hIdentityLoggerDatabase == null) {
    SQL_TConnect(SQL_OnConnectIdentityLogger, "identitylogger");
    CreateTimer(5.0, PerformClientCheck, client);
    return;
  }
  
  //Player is not banned on Steam/IP at this point
  //Get client steamid64 and IP address
  char ipaddress[16];
  char steamid64[18];
  
  GetClientIP(client, ipaddress, sizeof(ipaddress));
  GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
  
  char query[1024];
  
  //Query database for all SteamID64 addresses and IP addresses linked to this user
  Format(query, sizeof(query), "SELECT DISTINCT sid.steamid64, INET_NTOA(ips.ip) AS ip FROM steamids sid LEFT JOIN ipaddresses ips ON (sid.identityid = ips.identityid)  WHERE sid.identityid IN (SELECT DISTINCT iden.id FROM identities iden LEFT JOIN steamids sid ON sid.identityid = iden.id LEFT JOIN ipaddresses ips ON ips.identityid = iden.id WHERE sid.steamid64 = %s OR INET_NTOA(ips.ip) = '%s')", steamid64, ipaddress);
  
  SQL_TQuery(hIdentityLoggerDatabase, SQL_GetLinkedInformation, query, client);
}

public void SQL_GetLinkedInformation(Handle owner, Handle hndl, const char[] error, int client)
{
  if (hndl == null) {
    LogError("InvexSleuth: IdentityLogger Database query error: %s", error);
    return;
  }
  
  //Fetch data we need
  ArrayList steamid64list = new ArrayList(32);
  ArrayList iplist = new ArrayList(32);
  
  while (SQL_FetchRow(hndl)) {
    char db_steamid64[18], db_ip[16];
    
    SQL_FetchString(hndl, 0, db_steamid64, sizeof(db_steamid64));
    SQL_FetchString(hndl, 1, db_ip, sizeof(db_ip));
    
    //Add data to list if not duplicate data
    if (steamid64list.FindString(db_steamid64) == -1)
      steamid64list.PushString(db_steamid64);
    
    if (iplist.FindString(db_ip) == -1)
      iplist.PushString(db_ip);
  }
  
  //Return if we have no data in either list
  if (steamid64list.Length == 0 && iplist.Length == 0)
    return;
  
  //Ensure we don't go over the query length (minus a small safety for other parts of the query)
  if ((steamid64list.Length * 18) + (iplist.Length * 16) > SQL_SB_QUERY_SIZE - 1024) {
    LogError("InvexSleuth: Unusually large number of steamids or ips detected. Aborting");
    return;
  }
    
  //At this point, we need to create our ban check query for SourceBans
  char query[SQL_SB_QUERY_SIZE], sbprefix[64];
  g_cvar_sbprefix.GetString(sbprefix, sizeof(sbprefix));
  
  Format(query, sizeof(query), "SELECT length FROM %s_bans WHERE RemoveType IS NULL AND (ends > UNIX_TIMESTAMP() OR length = 0) AND (", sbprefix);
  
  //Check if steamid is not empty, append to query
  if (steamid64list.Length != 0) {
    //Start part
    Format(query, sizeof(query), "%s%s", query, "authid IN (");
  
    //Loop through steam id list
    for (int i = 0; i < steamid64list.Length; ++i) {
      char steamid64[18], steamid2variant1[32], steamid2variant2[32];
      steamid64list.GetString(i, steamid64, sizeof(steamid64));
      
      //Get SteamID 2 from SteamID64
      GetSteamId2(steamid64, steamid2variant1, sizeof(steamid2variant1));
      
      //Consider both universe prefix variants
      strcopy(steamid2variant2, sizeof(steamid2variant2), steamid2variant1);
      ReplaceString(steamid2variant2, sizeof(steamid2variant2), "STEAM_1", "STEAM_0");
      
      //Append to query
      Format(query, sizeof(query), "%s'%s','%s'", query, steamid2variant1, steamid2variant2);
      
      //If not last loop, also add a comma
      if (i != steamid64list.Length - 1) {
        Format(query, sizeof(query), "%s,", query);
      }
    }
  
    //End part
    Format(query, sizeof(query), "%s%s", query, ") ");
  }
  
  if (steamid64list.Length != 0 && iplist.Length != 0) {
    //Add OR connector
    Format(query, sizeof(query), "%s%s", query, " OR ");
  }
  
  //Check if iplist is not empty, append to query
  if (iplist.Length != 0) {
    //Start part
    Format(query, sizeof(query), "%s%s", query, "ip IN (");
  
    //Loop through IP address list
    for (int i = 0; i < iplist.Length; ++i) {
      char ipaddress[16];
      iplist.GetString(i, ipaddress, sizeof(ipaddress));
      
      //Append to query
      Format(query, sizeof(query), "%s'%s'", query, ipaddress);
      
      //If not last loop, also add a comma
      if (i != iplist.Length - 1) {
        Format(query, sizeof(query), "%s,", query);
      }
    }
  
    //End part
    Format(query, sizeof(query), "%s%s", query, ") ");
  }
  
  //Match end bracket
  Format(query, sizeof(query), "%s%s", query, ")");
  
  //Delete array lists
  delete steamid64list;
  delete iplist;
  
  //Query is now done, query the database
  SQL_TQuery(hSBDatabase, SQL_GetSBBanInformation, query, client);
}

public void SQL_GetSBBanInformation(Handle owner, Handle hndl, const char[] error, int client)
{
  if (hndl == null) {
    LogError("InvexSleuth: SourceBans Database query error: %s", error);
    return;
  }
  
  int longestBanLength = -1;
  
  while (SQL_FetchRow(hndl)) {
    int length = SQL_FetchInt(hndl, 0);
    if (length > longestBanLength)
      longestBanLength = length;
      
    //Cannot get longer ban than a permanent ban
    if (length == 0)
      break;
  }
  
  //If we did get ban results
  if (longestBanLength != -1) {
    //Compute new ban length
    //Keep in mind provided ban length is in seconds
    int newBanLength = RoundToFloor((longestBanLength/60) * g_cvar_banlengthmodifier.FloatValue);
    
    //Ban this player if they are still in the server
    if (IsClientConnected(client) && IsClientInGame(client)) {
      BanPlayer(client, newBanLength);
    }
  }
}

stock void BanPlayer(int client, int time)
{
  char reason[255];
  Format(reason, sizeof(reason), "[InvexSleuth] Duplicate account");
  SBBanPlayer(0, client, time, reason);
}
