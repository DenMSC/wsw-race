/*
Copyright (C) 2009-2010 Chasseur de bots

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

int numCheckpoints = 0;
bool demoRecording = false;

// msc: practicemode message
uint practiceModeMsg, defaultMsg;

class Position
{
    bool saved;
    Vec3 location;
    Vec3 angles;
    bool skipWeapons;
    int weapon;
    bool[] weapons;
    int[] ammos;
    float speed;

    Position()
    {
        this.weapons.resize( WEAP_TOTAL );
        this.ammos.resize( WEAP_TOTAL );
        this.clear();
    }

    ~Position() {}

    void clear()
    {
        this.saved = false;
        this.speed = 0;
    }

    void set( Vec3 location, Vec3 angles )
    {
        this.saved = true;
        this.location = location;
        this.angles = angles;
    }
}

///*****************************************************************
/// LOCAL FUNCTIONS
///*****************************************************************

// a player has just died. The script is warned about it so it can account scores
void RACE_playerKilled( Entity @target, Entity @attacker, Entity @inflicter )
{
    if ( @target == null || @target.client == null )
        return;

    RACE_GetPlayer( target.client ).cancelRace();
}

void RACE_SetUpMatch()
{
    int i, j;
    Entity @ent;
    Team @team;

    gametype.shootingDisabled = false;
    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = true;

    gametype.pickableItemsMask = gametype.spawnableItemsMask;
    gametype.dropableItemsMask = gametype.spawnableItemsMask;

    // clear player stats and scores, team scores

    for ( i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
    {
        @team = G_GetTeam( i );
        team.stats.clear();
    }

    G_RemoveDeadBodies();

    // ch : clear last recordSentTime
    lastRecordSent = levelTime;
}

///*****************************************************************
/// MODULE SCRIPT CALLS
///*****************************************************************

String randmap;
String randmap_passed = "";
uint randmap_time = 0;
uint randmap_matches;

uint[] maplist_page( maxClients );

bool GT_Command( Client @client, const String &cmdString, const String &argsString, int argc )
{
    if ( cmdString == "gametype" )
    {
        String response = "";
        Cvar fs_game( "fs_game", "", 0 );
        String manifest = gametype.manifest;

        response += "\n";
        response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
        response += "----------------\n";
        response += "Version: " + gametype.version + "\n";
        response += "Author: " + gametype.author + "\n";
        response += "Mod: " + fs_game.string + ( !manifest.empty() ? " (manifest: " + manifest + ")" : "" ) + "\n";
        response += "----------------\n";

        G_PrintMsg( client.getEnt(), response );
        return true;
    }
    else if ( cmdString == "cvarinfo" )
    {
        GENERIC_CheatVarResponse( client, cmdString, argsString, argc );
        return true;
    }
    else if ( cmdString == "callvotevalidate" )
    {
        String votename = argsString.getToken( 0 );

        if ( votename == "randmap" )
        {
            Cvar mapname( "mapname", "", 0 );
            String current = mapname.string.tolower();
            String pattern = argsString.getToken( 1 ).tolower();
            String[] maps;
            const String @map;
            String lmap;
            int i = 0;

            if ( levelTime - randmap_time > 1100 )
            {
              if ( pattern == "*" )
                  pattern = "";

              do
              {
                  @map = ML_GetMapByNum( i );
                  if ( @map != null)
                  {
                      lmap = map.tolower();
                      uint p;
                      bool match = false;
                      if ( pattern == "" )
                      {
                          match = true;
                      }
                      else
                      {
                          for ( p = 0; p < map.length(); p++ )
                          {
                              uint eq = 0;
                              while ( eq < pattern.length() && p + eq < lmap.length() )
                              {
                                  if ( lmap[p + eq] != pattern[eq] )
                                      break;
                                  eq++;
                              }
                              if ( eq == pattern.length() )
                              {
                                  match = true;
                                  break;
                              }
                          }
                      }
                      if ( match && map != current )
                          maps.insertLast( map );
                  }
                  i++;
              }
              while ( @map != null );

              if ( maps.length() == 0 )
              {
                  client.printMessage( "No matching maps\n" );
                  return false;
              }

              randmap = maps[rand() % maps.length()];
              randmap_matches = maps.length();
            }

            if ( levelTime - randmap_time < 80 )
            {
                G_PrintMsg( null, S_COLOR_YELLOW + "Chosen map: " + S_COLOR_WHITE + randmap + S_COLOR_YELLOW + " (out of " + S_COLOR_WHITE + randmap_matches + S_COLOR_YELLOW + " matches)\n" );
                return true;
            }

            randmap_time = levelTime;
        }
        else
        {
            client.printMessage( "Unknown callvote " + votename + "\n" );
            return false;
        }

        return true;
    }
    else if ( cmdString == "callvotepassed" )
    {
        String votename = argsString.getToken( 0 );

        if ( votename == "randmap" )
        {
            randmap_passed = randmap;
            match.launchState( MATCH_STATE_POSTMATCH );
        }

        return true;
    }
    else if ( cmdString == "racerestart" || cmdString == "kill" || cmdString == "join" )
    {
        if ( @client != null )
        {
            Player @player = RACE_GetPlayer( client );

            if ( pending_endmatch || match.getState() >= MATCH_STATE_POSTMATCH )
            {
              if ( !(player.inRace || player.postRace) )
                return true;
            }

            if ( player.inRace )
                player.cancelRace();

            if ( client.team != TEAM_SPECTATOR && player.client.getEnt().moveType == MOVETYPE_NOCLIP )
            {
                if ( player.loadPosition( false ) )
                {
                    player.noclipWeapon = player.savedPosition().weapon;
                }
                else
                {
                    player.noclipSpawn = true;
                    client.respawn( false );
                }
            }
            else
            {
                if ( client.team == TEAM_SPECTATOR )
                {
                    if ( gametype.isTeamBased )
                        return false;

                    client.team = TEAM_PLAYERS;
                    G_PrintMsg( null, client.name + S_COLOR_WHITE + " joined the " + G_GetTeam( client.team ).name + S_COLOR_WHITE + " team.\n" );
                }
                client.respawn( false );
            }
        }

        return true;
    }
    else if ( cmdString == "practicemode" )
    {
        RACE_GetPlayer( client ).togglePracticeMode();
        return true;
    }
    else if ( cmdString == "noclip" )
    {
        Player @player = RACE_GetPlayer( client );
        return player.toggleNoclip();
    }
    else if ( cmdString == "position" )
    {
        String action = argsString.getToken( 0 );
        if ( action == "save" )
        {
            return RACE_GetPlayer( client ).savePosition();
        }
        else if ( action == "load" )
        {
            return RACE_GetPlayer( client ).loadPosition( true );
        }
        else if ( action == "speed" && argsString.getToken( 1 ) != "" )
        {
            Position @position = RACE_GetPlayer( client ).savedPosition();
            String speed = argsString.getToken( 1 );
            if ( speed.locate( "+", 0 ) == 0 )
                position.speed += speed.substr( 1 ).toFloat();
            else if ( speed.locate( "-", 0 ) == 0 )
                position.speed -= speed.substr( 1 ).toFloat();
            else
                position.speed = speed.toFloat();
        }
        else if ( action == "clear" )
        {
            return RACE_GetPlayer( client ).clearPosition();
        }
        else
        {
            G_PrintMsg( client.getEnt(), "position <save | load | speed <value> | clear>\n" );
            return false;
        }

        return true;
    }
    else if ( cmdString == "top" )
    {
        RecordTime @top = levelRecords[0];
        if ( !top.saved )
        {
            client.printMessage( S_COLOR_RED + "No records yet.\n" );
        }
        else
        {
            Table table( "r r r l l" );
            for ( int i = 0; i < DISPLAY_RECORDS; i++ )
            {
                RecordTime @record = levelRecords[i];
                if ( record.saved )
                {
                    table.addCell( ( i + 1 ) + "." );
                    table.addCell( S_COLOR_GREEN + RACE_TimeToString( record.finishTime ) );
                    table.addCell( S_COLOR_YELLOW + "[+" + RACE_TimeToString( record.finishTime - top.finishTime ) + "]" );
                    table.addCell( S_COLOR_WHITE + record.playerName );
                    if ( record.login != "" )
                        table.addCell( "(" + S_COLOR_YELLOW + record.login + S_COLOR_WHITE + ")" );
                    else
                        table.addCell( "" );
                }
            }
            uint rows = table.numRows();
            for ( uint i = 0; i < rows; i++ )
                client.printMessage( table.getRow( i ) + "\n" );
        }

        return true;
    }
    else if ( cmdString == "maplist" )
    {
      String arg1 = argsString.getToken( 0 ).tolower();
      String arg2 = argsString.getToken( 1 ).tolower();
      String pattern;
      uint old_page = maplist_page[client.playerNum];
      int page;
      int last_page;

      if ( arg1 == "" )
      {
        client.printMessage( "maplist <* | pattern> [<page# | prev | next>]\n" );
        return false;
      }

      pattern = arg1;

      if ( arg2 == "next" )
      {
        page = old_page + 1;
      }
      else if ( arg2 == "prev" )
      {
        page = old_page - 1;
      }
      else if ( arg2.isNumeric() )
      {
        page = arg2.toInt()-1;
      }
      else if ( arg2 == "" )
      {
        page = 0;
      }
      else
      {
        client.printMessage( "Page must be a number, \"prev\" or \"next\".\n" );
        return false;
      }

      String[] maps;
      const String @map;
      String lmap;
      uint i = 0;

      if ( pattern == "*" )
          pattern = "";

      uint longest = 0;
      String longest_name;

      do
      {
          @map = ML_GetMapByNum( i );
          if ( @map != null)
          {
              lmap = map.tolower();
              uint p;
              bool match = false;
              if ( pattern == "" )
              {
                  match = true;
              }
              else
              {
                  for ( p = 0; p < map.length(); p++ )
                  {
                      uint eq = 0;
                      while ( eq < pattern.length() && p + eq < lmap.length() )
                      {
                          if ( lmap[p + eq] != pattern[eq] )
                              break;
                          eq++;
                      }
                      if ( eq == pattern.length() )
                      {
                          match = true;
                          break;
                      }
                  }
              }
              if ( match )
                  maps.insertLast( map );

              if ( map.length() > longest )
              {
                longest = map.length();
                longest_name = map;
              }
          }
          i++;
      }
      while ( @map != null );

      if ( maps.length() == 0 )
      {
          client.printMessage( "No matching maps\n" );
          return false;
      }

      Table maplist("l l l");

      last_page = maps.length()/30;

      if ( page < 0 || page > last_page )
      {
        client.printMessage( "Page doesn't exist.\n" );
        return false;
      }
      maplist_page[client.playerNum] = page;

      uint start = 30*page;
      uint end = 30*page+30;
      if ( end > maps.length() )
        end = maps.length();

      for ( i = start; i < end; i++ )
      {
        if ( i >= maps.length() )
          break;
        maplist.addCell( S_COLOR_WHITE + maps[i] );
      }

      client.printMessage( S_COLOR_YELLOW + "Found " + S_COLOR_WHITE + maps.length() + S_COLOR_YELLOW + " maps" +
        S_COLOR_WHITE + " (" + (start+1) + "-" + end + "), " + S_COLOR_YELLOW + "page " + S_COLOR_WHITE + (page+1) + "/" + (last_page+1) + "\n" );

      for ( i = 0; i < maplist.numRows(); i++ )
        client.printMessage( maplist.getRow(i) + "\n" );

      return true;
    }
    else if ( cmdString == "help" )
    {
      String arg1 = argsString.getToken( 0 ).tolower();
      String arg2 = argsString.getToken( 1 ).tolower();

      if ( arg1 == "" )
      {
        Table cmdlist( S_COLOR_YELLOW + "l " + S_COLOR_WHITE + "l" );
        cmdlist.addCell( "/kill /racerestart" );
        cmdlist.addCell( "Respawns you." );

        cmdlist.addCell( "/practicemode" );
        cmdlist.addCell( "Toggles between race and practicemode." );

        cmdlist.addCell( "/noclip" );
        cmdlist.addCell( "Lets you move freely through the world whilst in practicemode." );

        cmdlist.addCell( "/position save" );
        cmdlist.addCell( "Saves your position including your weapons as the new spawn position." );

        cmdlist.addCell( "/position load" );
        cmdlist.addCell( "Teleports you to your saved position." );

        cmdlist.addCell( "/position speed" );
        cmdlist.addCell( "Sets the speed at which you spawn in practicemode." );

        cmdlist.addCell( "/position clear" );
        cmdlist.addCell( "Resets your weapons and spawn position to their defaults." );

        cmdlist.addCell( "/top" );
        cmdlist.addCell( "Shows the top record times for the current map." );

        cmdlist.addCell( "/maplist" );
        cmdlist.addCell( "Lets you search available maps." );

        cmdlist.addCell( "/callvote map" );
        cmdlist.addCell( "Calls a vote for the specified map." );

        cmdlist.addCell( "/callvote randmap" );
        cmdlist.addCell( "Calls a vote for a random map in the current mappool." );

        for ( uint i = 0; i < cmdlist.numRows(); i++ )
          client.printMessage( cmdlist.getRow(i) + "\n" );

        client.printMessage( S_COLOR_WHITE + "use " + S_COLOR_YELLOW + "/help <cmd> " + S_COLOR_WHITE + "for additional information." + "\n");
      }
      else if ( arg1 == "kill" || arg1 == "racerestart" )
      {
        client.printMessage( S_COLOR_YELLOW + "/kill /racerestart" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Respawns you. I mean srsly.. that's it." + "\n" );
      }
      else if ( arg1 == "practicemode" )
      {
        client.printMessage( S_COLOR_YELLOW + "/practicemode" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Toggles between race and practicemode. Race mode is the only mode in which your time will" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  be recorded. Practicemode is used to practice specific parts of the map. Some commands are" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  restricted to practicemode." + "\n" );
      }
      else if ( arg1 == "noclip" )
      {
        client.printMessage( S_COLOR_YELLOW + "/noclip" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Lets you move freely through the world whilst in practicemode. Use this command to get more" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  control over your position when using /position save. Only works in practicemode." + "\n" );
      }
      else if ( arg1 == "position" && arg2 == "save" )
      {
        client.printMessage( S_COLOR_YELLOW + "/position save" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Saves your position including your weapons as the new spawn position. You can save a separate" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  position for prerace and practicemode, depending on which mode you are in when using the command." + "\n" );
        client.printMessage( S_COLOR_WHITE + "  Note: Using this command during race will save your position for practicemode." + "\n" );
      }
      else if ( arg1 == "position" && arg2 == "load" )
      {
        client.printMessage( S_COLOR_YELLOW + "/position load" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Teleports you to your saved position depending on which mode you are in." + "\n" );
        client.printMessage( S_COLOR_WHITE + "  Note: This command does not work during race." + "\n" );
      }
      else if ( arg1 == "position" && arg2 == "speed" )
      {
        client.printMessage( S_COLOR_YELLOW + "/position speed <value>" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Example: /position speed 1000 - Sets your spawn speed to 1000." + "\n" );
        client.printMessage( S_COLOR_WHITE + "  Sets the speed at which you spawn in practicemode. This does not affect prerace speed." + "\n" );
        client.printMessage( S_COLOR_WHITE + "  Use /position speed 0 to reset. Note: You don't get spawn speed while in noclip mode." + "\n" );
      }
      else if ( arg1 == "position" && arg2 == "clear" )
      {
        client.printMessage( S_COLOR_YELLOW + "/position clear" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Resets your weapons and spawn position to their defaults." + "\n" );
      }
      else if ( arg1 == "top" )
      {
        client.printMessage( S_COLOR_YELLOW + "/top" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Shows a list of the top record times for the current map along with the names and time" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  difference compared to the number 1 time. To see all lists visit: http://livesow.net/race." + "\n" );
      }
      else if ( arg1 == "maplist" )
      {
        client.printMessage( S_COLOR_YELLOW + "/maplist <* | pattern> [<page# | prev | next>]" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Shows a list of available maps. Use wildcard '*' to list all maps. Alternatively, specify a" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  pattern keyword for a list of maps containing the pattern as a partial match. The second" + "\n" );
        client.printMessage( S_COLOR_WHITE + "  argument is optional and is used to browse multiple pages of results." + "\n" );
      }
      else if ( arg1 == "callvote" && arg2 == "map" )
      {
        client.printMessage( S_COLOR_YELLOW + "/callvote map <mapname>" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Calls a vote for the specified map. You can use /maplist to search for a map." + "\n" );
      }
      else if ( arg1 == "callvote" && arg2 == "randmap" )
      {
        client.printMessage( S_COLOR_YELLOW + "/callvote randmap <* | pattern>" + "\n" );
        client.printMessage( S_COLOR_WHITE + "- Calls a vote for a random map in the current mappool. Use wildcard '*' to match any map." + "\n" );
        client.printMessage( S_COLOR_WHITE + "  Alternatively, specify a pattern keyword for a map containing the pattern as a partial match." + "\n" );
      }
      else
      {
        client.printMessage( S_COLOR_WHITE + "Command not found.\n");
      }

      return true;
    }

    G_PrintMsg( null, "unknown: " + cmdString + "\n" );

    return false;
}

// When this function is called the weights of items have been reset to their default values,
// this means, the weights *are set*, and what this function does is scaling them depending
// on the current bot status.
// Player, and non-item entities don't have any weight set. So they will be ignored by the bot
// unless a weight is assigned here.
bool GT_UpdateBotStatus( Entity @self )
{
    return false; // let the default code handle it itself
}

// select a spawning point for a player
Entity @GT_SelectSpawnPoint( Entity @self )
{
    return GENERIC_SelectBestRandomSpawnPoint( self, "info_player_deathmatch" );
}

String @GT_ScoreboardMessage( uint maxlen )
{
    String scoreboardMessage = "";
    String entry;
    Team @team;
    Entity @ent;
    Player @player;
    int i;
    uint minTime, currentTime;
    bool playerFound;
    //int readyIcon;

    @team = G_GetTeam( TEAM_PLAYERS );

    // &t = team tab, team tag, team score (doesn't apply), team ping (doesn't apply)
    entry = "&t " + int( TEAM_PLAYERS ) + " 0 " + team.ping + " ";
    if ( scoreboardMessage.length() + entry.length() < maxlen )
        scoreboardMessage += entry;

    minTime = 0;

    do
    {
        playerFound = false;
        currentTime = 0;

        // find the next best time
        for ( i = 0; @team.ent( i ) != null; i++ )
        {
            @ent = team.ent( i );
            @player = RACE_GetPlayer( ent.client );

            if ( player.hasTime && player.bestFinishTime >= minTime && ( !playerFound || player.bestFinishTime < currentTime ) )
            {
                playerFound = true;
                currentTime = player.bestFinishTime;
            }
        }
        if ( playerFound )
        {
            // add all players with this time
            for ( i = 0; @team.ent( i ) != null; i++ )
            {
                @ent = team.ent( i );
                @player = RACE_GetPlayer( ent.client );

                if ( player.hasTime && player.bestFinishTime == currentTime )
                {
                    entry = player.scoreboardEntry();
                    if ( scoreboardMessage.length() + entry.length() < maxlen )
                        scoreboardMessage += entry;
                }
            }
            minTime = currentTime + 1;
        }
    }
    while ( playerFound );

    // add players without time
    for ( i = 0; @team.ent( i ) != null; i++ )
    {
        @ent = team.ent( i );
        @player = RACE_GetPlayer( ent.client );

        if ( !player.hasTime )
        {
            entry = player.scoreboardEntry();
            if ( scoreboardMessage.length() + entry.length() < maxlen )
                scoreboardMessage += entry;
        }
    }

    return scoreboardMessage;
}

// Some game actions trigger score events. These are events not related to killing
// oponents, like capturing a flag
// Warning: client can be null
void GT_ScoreEvent( Client @client, const String &score_event, const String &args )
{
    if ( score_event == "dmg" )
    {
    }
    else if ( score_event == "kill" )
    {
        Entity @attacker = null;

        if ( @client != null )
            @attacker = client.getEnt();

        int arg1 = args.getToken( 0 ).toInt();
        int arg2 = args.getToken( 1 ).toInt();

        // target, attacker, inflictor
        RACE_playerKilled( G_GetEntity( arg1 ), attacker, G_GetEntity( arg2 ) );
    }
    else if ( score_event == "award" )
    {
    }
    else if ( score_event == "enterGame" )
    {
        if ( @client != null )
        {
            RACE_GetPlayer( client ).clear();
            RACE_UpdateHUDTopScores();
        }

        // ch : begin fetching records over interweb
        // MM_FetchRaceRecords( client.getEnt() );
    }
    else if ( score_event == "userinfochanged" )
    {
        if ( @client != null )
        {
            String login = client.getMMLogin();
            if ( login != "" )
            {
                Player @player = RACE_GetPlayer( client );
                // find out if he holds a record better than his current time
                for ( int i = 0; i < MAX_RECORDS; i++ )
                {
                    if ( !levelRecords[i].saved )
                        break;
                    if ( levelRecords[i].login == login
                            && ( !player.hasTime || levelRecords[i].finishTime < player.bestFinishTime ) )
                    {
                        player.setBestTime( levelRecords[i].finishTime );
                        for ( int j = 0; j < numCheckpoints; j++ )
                            player.bestSectorTimes[j] = levelRecords[i].sectorTimes[j];
                        break;
                    }
                }
            }
        }
    }
}

// a player is being respawned. This can happen from several ways, as dying, changing team,
// being moved to ghost state, be placed in respawn queue, being spawned from spawn queue, etc
void GT_PlayerRespawn( Entity @ent, int old_team, int new_team )
{
    if ( pending_endmatch )
    {
      if ( ent.client.team != TEAM_SPECTATOR )
      {
        ent.client.team = TEAM_SPECTATOR;
        ent.client.respawn(false);
      }

      if ( !Pending_AnyRacing() )
      {
        pending_endmatch = false;
        match.launchState(MATCH_STATE_POSTMATCH);
      }

      return;
    }

    Player @player = RACE_GetPlayer( ent.client );
    player.cancelRace();

    player.setQuickMenu();
    player.updateScore();

    if ( ent.isGhosting() )
        return;

    // set player movement to pass through other players
    ent.client.pmoveFeatures = ent.client.pmoveFeatures | PMFEAT_GHOSTMOVE;

    if ( gametype.isInstagib )
        ent.client.inventoryGiveItem( WEAP_INSTAGUN );
    else
    {
        ent.client.inventorySetCount( WEAP_GUNBLADE, 1 );
    }

    // select rocket launcher if available
    if ( ent.client.canSelectWeapon( WEAP_ROCKETLAUNCHER ) )
        ent.client.selectWeapon( WEAP_ROCKETLAUNCHER );
    else
        ent.client.selectWeapon( -1 ); // auto-select best weapon in the inventory

    G_RemoveProjectiles( ent );
    RS_ResetPjState( ent.client.playerNum );
    // for accuracy.as, fixes issues with position save in prerace (kinda)
    scoreCounter[ent.client.playerNum] = 0;

    player.loadPosition( false );

    // msc: permanent practicemode message
    if ( player.practicing )
    {
      ent.client.setHelpMessage(practiceModeMsg);
    } else {
      ent.client.setHelpMessage(defaultMsg);
    }

    if ( player.noclipSpawn )
    {
        if ( player.practicing )
        {
            ent.moveType = MOVETYPE_NOCLIP;
            ent.velocity = Vec3(0,0,0);
            player.noclipWeapon = ent.weapon;
        }
        player.noclipSpawn = false;
    }
    else
    {
        // add a teleportation effect
        // ent.respawnEffect();

        if ( !player.practicing && !player.heardReady )
        {
            int soundIndex = G_SoundIndex( "sounds/announcer/countdown/ready0" + (1 + (rand() & 1)) );
            G_AnnouncerSound( ent.client, soundIndex, GS_MAX_TEAMS, false, null );
            player.heardReady = true;
        }
    }
}

// Thinking function. Called each frame
void GT_ThinkRules()
{
    if ( match.scoreLimitHit() || match.timeLimitHit() || match.suddenDeathFinished() )
        match.launchState( match.getState() + 1 );

    if ( match.getState() >= MATCH_STATE_POSTMATCH )
        return;

    GENERIC_Think();

    if ( match.getState() == MATCH_STATE_PLAYTIME )
    {
        // if there is no player in TEAM_PLAYERS finish the match and restart
        if ( G_GetTeam( TEAM_PLAYERS ).numPlayers == 0 && demoRecording )
        {
            match.stopAutorecord();
            demoRecording = false;
        }
        else if ( !demoRecording && G_GetTeam( TEAM_PLAYERS ).numPlayers > 0 )
        {
            match.startAutorecord();
            demoRecording = true;
        }
    }

    // set all clients race stats
    Client @client;
    Player @player;

    for ( int i = 0; i < maxClients; i++ )
    {
        @client = G_GetClient( i );
        if ( client.state() < CS_SPAWNED )
            continue;

        // disable gunblade autoattack
        client.pmoveFeatures = client.pmoveFeatures & ~PMFEAT_GUNBLADEAUTOATTACK;

        // always clear all before setting
        client.setHUDStat( STAT_PROGRESS_SELF, 0 );
        //client.setHUDStat( STAT_PROGRESS_OTHER, 0 );
        client.setHUDStat( STAT_IMAGE_SELF, 0 );
        client.setHUDStat( STAT_IMAGE_OTHER, 0 );
        client.setHUDStat( STAT_PROGRESS_ALPHA, 0 );
        client.setHUDStat( STAT_PROGRESS_BETA, 0 );
        client.setHUDStat( STAT_IMAGE_ALPHA, 0 );
        client.setHUDStat( STAT_IMAGE_BETA, 0 );
        client.setHUDStat( STAT_MESSAGE_SELF, 0 );
        client.setHUDStat( STAT_MESSAGE_OTHER, 0 );
        client.setHUDStat( STAT_MESSAGE_ALPHA, 0 );
        client.setHUDStat( STAT_MESSAGE_BETA, 0 );

        // all stats are set to 0 each frame, so it's only needed to set a stat if it's going to get a value
        @player = RACE_GetPlayer( client );
        if ( player.inRace )
            client.setHUDStat( STAT_TIME_SELF, player.raceTime() / 100 );

        client.setHUDStat( STAT_TIME_BEST, player.bestFinishTime / 100 );
        client.setHUDStat( STAT_TIME_RECORD, levelRecords[0].finishTime / 100 );

        client.setHUDStat( STAT_TIME_ALPHA, -9999 );
        client.setHUDStat( STAT_TIME_BETA, -9999 );

        if ( levelRecords[0].playerName.length() > 0 )
            client.setHUDStat( STAT_MESSAGE_OTHER, CS_GENERAL );
        if ( levelRecords[1].playerName.length() > 0 )
            client.setHUDStat( STAT_MESSAGE_ALPHA, CS_GENERAL + 1 );
        if ( levelRecords[2].playerName.length() > 0 )
            client.setHUDStat( STAT_MESSAGE_BETA, CS_GENERAL + 2 );

        // msc: temporary MAX_ACCEL replacement
        if ( frameTime > 0 )
        {
          float cgframeTime = float(frameTime)/1000;
          int base_speed = int(client.pmoveMaxSpeed);
          float base_accel = base_speed * cgframeTime;
          Vec3 vel = client.getEnt().velocity;
          vel.z = 0;
          float speed = vel.length();
          int max_accel = int( ( sqrt( speed*speed + base_accel * ( 2 * base_speed - base_accel ) ) - speed ) / cgframeTime );
          client.setHUDStat( STAT_PROGRESS_SELF, max_accel );
        }

    Entity @ent = @client.getEnt();
        if ( ent.client.state() >= CS_SPAWNED && ent.team != TEAM_SPECTATOR )
        {
            if ( ent.health > ent.maxHealth ) {
                ent.health -= ( frameTime * 0.001f );
                // fix possible rounding errors
                if( ent.health < ent.maxHealth ) {
                    ent.health = ent.maxHealth;
                }
            }
        }
    }

    // ch : send intermediate results
    if ( ( lastRecordSent + RECORD_SEND_INTERVAL ) >= levelTime )
    {

    }
}

bool pending_endmatch = false;

// The game has detected the end of the match state, but it
// doesn't advance it before calling this function.
// This function must give permission to move into the next
// state by returning true.
bool GT_MatchStateFinished( int incomingMatchState )
{
    if ( incomingMatchState == MATCH_STATE_WAITEXIT )
    {
        match.stopAutorecord();
        demoRecording = false;

        // ch : also send rest of results
        RACE_WriteTopScores();

        G_CmdExecute("set g_inactivity_maxtime 90\n");

        if ( randmap_passed != "" )
            G_CmdExecute( "map " + randmap_passed );
    }

    if ( incomingMatchState == MATCH_STATE_POSTMATCH )
    { // msc: check for overtime
      G_CmdExecute("set g_inactivity_maxtime 5\n");
      if ( Pending_AnyRacing(true) )
      {
        G_AnnouncerSound( null, G_SoundIndex( "sounds/announcer/overtime/overtime" ), GS_MAX_TEAMS, false, null );
        pending_endmatch = true;
        return false;
      }
    }

    return true;
}

// the match state has just moved into a new state. Here is the
// place to set up the new state rules
void GT_MatchStateStarted()
{
    // hettoo : skip warmup and countdown
    if ( match.getState() < MATCH_STATE_PLAYTIME )
    {
        match.launchState( MATCH_STATE_PLAYTIME );
        return;
    }

    switch ( match.getState() )
    {
    case MATCH_STATE_PLAYTIME:
        RACE_SetUpMatch();
        break;

    case MATCH_STATE_POSTMATCH:
        gametype.pickableItemsMask = 0;
        gametype.dropableItemsMask = 0;
        GENERIC_SetUpEndMatch();
        break;

    default:
        break;
    }
}

// the gametype is shutting down cause of a match restart or map change
void GT_Shutdown()
{
}

// The map entities have just been spawned. The level is initialized for
// playing, but nothing has yet started.
void GT_SpawnGametype()
{
    //G_Print( "numCheckPoints: " + numCheckpoints + "\n" );

    //TODO: fix in source, /kill should reset touch timeouts.
    for ( int i = 0; i < numEntities; i++ )
    {
        Entity@ ent = G_GetEntity(i);
        if ( ent.classname == "trigger_multiple" )
        {
            Entity@[] targets = ent.findTargets();
            for ( uint j = 0; j < targets.length; j++ )
            {
                Entity@ target = targets[j];
                if ( target.classname == "target_starttimer" )
                {
                    ent.wait = 0;
                    break;
                }
            }
        }
    }

    // setup the checkpoints arrays sizes adjusted to numCheckPoints
    for ( int i = 0; i < maxClients; i++ )
        players[i].setupArrays( numCheckpoints );

    for ( int i = 0; i < MAX_RECORDS; i++ )
        levelRecords[i].setupArrays( numCheckpoints );

    RACE_LoadTopScores();
}

// Important: This function is called before any entity is spawned, and
// spawning entities from it is forbidden. If you want to make any entity
// spawning at initialization do it in GT_SpawnGametype, which is called
// right after the map entities spawning.

void GT_InitGametype()
{
    gametype.title = "Race";
    gametype.version = "1.02";
    gametype.author = "Warsow Development Team";

    // if the gametype doesn't have a config file, create it
    if ( !G_FileExists( "configs/server/gametypes/" + gametype.name + ".cfg" ) )
    {
        String config;

        // the config file doesn't exist or it's empty, create it
        config = "// '" + gametype.title + "' gametype configuration file\n"
                 + "// This config will be executed each time the gametype is started\n"
                 + "\n\n// map rotation\n"
                 + "set g_maplist \"\" // list of maps in automatic rotation\n"
                 + "set g_maprotation \"0\"   // 0 = same map, 1 = in order, 2 = random\n"
                 + "\n// game settings\n"
                 + "set g_scorelimit \"0\"\n"
                 + "set g_timelimit \"0\"\n"
                 + "set g_warmup_timelimit \"0\"\n"
                 + "set g_match_extendedtime \"0\"\n"
                 + "set g_allow_falldamage \"0\"\n"
                 + "set g_allow_selfdamage \"0\"\n"
                 + "set g_allow_teamdamage \"0\"\n"
                 + "set g_allow_stun \"0\"\n"
                 + "set g_teams_maxplayers \"0\"\n"
                 + "set g_teams_allow_uneven \"0\"\n"
                 + "set g_countdown_time \"5\"\n"
                 + "set g_maxtimeouts \"0\" // -1 = unlimited\n"
                 + "set g_challengers_queue \"0\"\n"
                 + "\necho " + gametype.name + ".cfg executed\n";

        G_WriteFile( "configs/server/gametypes/" + gametype.name + ".cfg", config );
        G_Print( "Created default config file for '" + gametype.name + "'\n" );
        G_CmdExecute( "exec configs/server/gametypes/" + gametype.name + ".cfg silent" );
    }

    gametype.spawnableItemsMask = ( IT_WEAPON | IT_AMMO | IT_ARMOR | IT_POWERUP | IT_HEALTH );
    if ( gametype.isInstagib )
        gametype.spawnableItemsMask &= ~uint( G_INSTAGIB_NEGATE_ITEMMASK );

    gametype.respawnableItemsMask = gametype.spawnableItemsMask;
    gametype.dropableItemsMask = 0;
    gametype.pickableItemsMask = ( gametype.spawnableItemsMask | gametype.dropableItemsMask );

    gametype.isTeamBased = false;
    gametype.isRace = true;
    gametype.hasChallengersQueue = false;
    gametype.maxPlayersPerTeam = 0;

    gametype.ammoRespawn = 1;
    gametype.armorRespawn = 1;
    gametype.weaponRespawn = 1;
    gametype.healthRespawn = 1;
    gametype.powerupRespawn = 1;
    gametype.megahealthRespawn = 1;
    gametype.ultrahealthRespawn = 1;

    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    gametype.mathAbortDisabled = true;
    gametype.shootingDisabled = false;
    gametype.infiniteAmmo = true;
    gametype.canForceModels = true;
    gametype.canShowMinimap = false;
    gametype.teamOnlyMinimap = true;

    gametype.spawnpointRadius = 0;

    if ( gametype.isInstagib )
        gametype.spawnpointRadius *= 2;

    gametype.inverseScore = true;

    // set spawnsystem type
    for ( int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++ )
        gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_INSTANT, 0, 0, false );

    // define the scoreboard layout
    G_ConfigString( CS_SCB_PLAYERTAB_LAYOUT, "%n 112 %s 52 %t 96 %s 48 %l 48 %s 52" );
    G_ConfigString( CS_SCB_PLAYERTAB_TITLES, "Name Clan Time Diff Ping Racing" );

    // add commands
    G_RegisterCommand( "gametype" );
    G_RegisterCommand( "racerestart" );
    G_RegisterCommand( "kill" );
    G_RegisterCommand( "join" );
    G_RegisterCommand( "practicemode" );
    G_RegisterCommand( "noclip" );
    G_RegisterCommand( "position" );
    G_RegisterCommand( "top" );
    G_RegisterCommand( "maplist" );
    G_RegisterCommand( "help" );

    // add votes
    G_RegisterCallvote( "randmap", "<* | pattern>", "string", "Changes to a random map" );

    // msc: practicemode message
    practiceModeMsg = G_RegisterHelpMessage(S_COLOR_CYAN + "Practicing");
    defaultMsg = G_RegisterHelpMessage(" ");

    demoRecording = false;

    G_Print( "Gametype '" + gametype.title + "' initialized\n" );
}
