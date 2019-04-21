enum eMenuItems
{
    MI_EMPTY,
    MI_RESTART_RACE,
    MI_ENTER_PRACTICE,
    MI_LEAVE_PRACTICE,
    MI_NOCLIP_ON,
    MI_NOCLIP_OFF,
    MI_SAVE_POSITION,
    MI_LOAD_POSITION,
    MI_CLEAR_POSITION
};

array<const String @> menuItems = {
    '"" ""',
    '"Restart race" "racerestart"',
    '"Enter practice mode" "practicemode" ',
    '"Leave practice mode" "practicemode" ',
    '"Enable noclip mode" "noclip" ',
    '"Disable noclip mode" "noclip" ',
    '"Save position" "position save" ',
    '"Load saved position" "position load" ',
    '"Clear saved position" "position clear" '
};

Player[] players( maxClients );

class Player
{
    Client @client;
    uint[] sectorTimes;
    uint[] bestSectorTimes;
    uint startTime;
    uint finishTime;
    bool hasTime;
    uint bestFinishTime;
    bool noclipSpawn;
    Table report( S_COLOR_ORANGE + "l " + S_COLOR_WHITE + "r " + S_COLOR_ORANGE + "/ l r " + S_COLOR_ORANGE + "/ l r" );
    int currentSector;
    bool inRace;
    bool postRace;
    bool practicing;
    uint practicemodeFinishTime;
    bool arraysSetUp;

    bool heardReady;
    bool heardGo;

    // hettoo : practicemode
    int noclipWeapon;
    Position practicePosition;
    Position preRacePosition;

    void setupArrays( int size )
    {
        this.sectorTimes.resize( size );
        this.bestSectorTimes.resize( size );
        this.arraysSetUp = true;
        this.clear();
    }

    void clear()
    {
        @this.client = null;
        this.currentSector = 0;
        this.inRace = false;
        this.postRace = false;
        this.practicing = false;
        this.practicemodeFinishTime = 0;
        this.startTime = 0;
        this.finishTime = 0;
        this.hasTime = false;
        this.bestFinishTime = 0;
        this.noclipSpawn = false;

        this.heardReady = false;
        this.heardGo = false;

        this.practicePosition.clear();
        this.preRacePosition.clear();

        if ( !this.arraysSetUp )
            return;

        for ( int i = 0; i < numCheckpoints; i++ )
        {
            this.sectorTimes[i] = 0;
            this.bestSectorTimes[i] = 0;
        }
    }

    Player()
    {
        this.arraysSetUp = false;
        this.clear();
    }

    ~Player() {}

    void setBestTime( uint time )
    {
        this.hasTime = true;
        this.bestFinishTime = time;
        this.updateScore();
    }

    void updateScore()
    {
        this.client.stats.setScore( this.bestFinishTime / 10 );
    }

    String @scoreboardEntry()
    {
        Entity @ent = this.client.getEnt();
        int playerID = ( ent.isGhosting() && ( match.getState() == MATCH_STATE_PLAYTIME ) ) ? -( ent.playerNum + 1 ) : ent.playerNum;
        String racing;

        if ( this.practicing )
            racing = S_COLOR_CYAN + "No";
        else if ( this.inRace )
            racing = S_COLOR_GREEN + "Yes";
        else
            racing = S_COLOR_RED + "No";
        String diff;
        if ( this.hasTime && levelRecords[0].saved && this.bestFinishTime >= levelRecords[0].finishTime )
        {
            if ( this.bestFinishTime == levelRecords[0].finishTime )
                diff = S_COLOR_GREEN + "0";
            else if ( this.bestFinishTime >= levelRecords[0].finishTime + 1000 )
                diff = S_COLOR_RED + "+";
            else
                diff = S_COLOR_YELLOW + ( this.bestFinishTime - levelRecords[0].finishTime );
        }
        else
        {
            diff = "-";
        }
        return "&p " + playerID + " " + ent.client.clanName + " " + this.bestFinishTime + " " + diff + " " + ent.client.ping + " " + racing + " ";
    }

    bool preRace()
    {
        return !this.inRace && !this.practicing && !this.postRace && this.client.team != TEAM_SPECTATOR;
    }

    void setQuickMenu()
    {
        String s = '';
        Position @position = this.savedPosition();

        s += menuItems[MI_RESTART_RACE];
        if ( this.practicing )
        {
            s += menuItems[MI_LEAVE_PRACTICE];
            if ( this.client.team != TEAM_SPECTATOR )
            {
                if ( this.client.getEnt().moveType == MOVETYPE_NOCLIP )
                    s += menuItems[MI_NOCLIP_OFF];
                else
                    s += menuItems[MI_NOCLIP_ON];
            }
            else
            {
                s += menuItems[MI_EMPTY];
            }
            s += menuItems[MI_SAVE_POSITION];
            if ( position.saved )
                s += menuItems[MI_LOAD_POSITION] +
                     menuItems[MI_CLEAR_POSITION];
        }
        else
        {
            s += menuItems[MI_ENTER_PRACTICE] +
                 menuItems[MI_EMPTY] +
                 menuItems[MI_SAVE_POSITION];
            if ( position.saved && ( this.preRace() || this.client.team == TEAM_SPECTATOR ) )
                s += menuItems[MI_LOAD_POSITION] +
                     menuItems[MI_CLEAR_POSITION];
        }

        GENERIC_SetQuickMenu( this.client, s );
    }

    bool toggleNoclip()
    {
        Entity @ent = this.client.getEnt();
        if ( !this.practicing )
        {
            G_PrintMsg( ent, "Noclip mode is only available in practice mode.\n" );
            return false;
        }
        if ( this.client.team == TEAM_SPECTATOR )
        {
            G_PrintMsg( ent, "Noclip mode is not available for spectators.\n" );
            return false;
        }

        String msg;
        if ( ent.moveType == MOVETYPE_PLAYER )
        {
            ent.moveType = MOVETYPE_NOCLIP;
            this.noclipWeapon = ent.weapon;
            msg = "Noclip mode enabled.";
        }
        else
        {
            ent.moveType = MOVETYPE_PLAYER;
            this.client.selectWeapon( this.noclipWeapon );
            msg = "Noclip mode disabled.";
        }

        G_PrintMsg( ent, msg + "\n" );

        this.setQuickMenu();

        return true;
    }

    Position @savedPosition()
    {
        if ( this.preRace() )
            return preRacePosition;
        else
            return practicePosition;
    }

    bool loadPosition( bool verbose )
    {
        Entity @ent = this.client.getEnt();
        if ( !this.practicing && this.client.team != TEAM_SPECTATOR && !this.preRace() )
        {
            if ( verbose )
                G_PrintMsg( ent, "Position loading is not available during a race.\n" );
            return false;
        }

        Position @position = this.savedPosition();

        if ( !position.saved )
        {
            if ( verbose )
                G_PrintMsg( ent, "No position has been saved yet.\n" );
            return false;
        }

        ent.origin = position.location;
        ent.angles = position.angles;

        if ( !position.skipWeapons )
        {
            for ( int i = WEAP_NONE + 1; i < WEAP_TOTAL; i++ )
            {
                if ( position.weapons[i] )
                    this.client.inventoryGiveItem( i );
                Item @item = G_GetItem( i );
                this.client.inventorySetCount( item.ammoTag, position.ammos[i] );
            }
            this.client.selectWeapon( position.weapon );
        }

        if ( this.practicing )
        {
            if ( ent.moveType != MOVETYPE_NOCLIP )
            {
                Vec3 a, b, c;
                position.angles.angleVectors( a, b, c );
                a.z = 0;
                a.normalize();
                a *= position.speed;
                ent.set_velocity( a );
            } else {
                ent.set_velocity( Vec3() );
            }
        }
        else if ( this.preRace() )
        {
            ent.set_velocity( Vec3() );
        }

        return true;
    }

    bool savePosition()
    {
        Client @ref = this.client;
        if ( this.client.team == TEAM_SPECTATOR && this.client.chaseActive )
            @ref = G_GetEntity( this.client.chaseTarget ).client;
        Entity @ent = ref.getEnt();

        if ( this.preRace() )
        {
            Vec3 mins, maxs;
            ent.getSize( mins, maxs );
            Vec3 down = ent.origin;
            down.z -= 1;
            Trace tr;
            if ( !tr.doTrace( ent.origin, mins, maxs, down, ent.entNum, MASK_PLAYERSOLID ) )
            {
                G_PrintMsg( this.client.getEnt(), "You can only save your prerace position on solid ground.\n" );
                return false;
            }
            if ( maxs.z < 40 )
            {
                G_PrintMsg( this.client.getEnt(), "You can't save your prerace position while crouched.\n" );
                return false;
            }
        }

        Position @position = this.savedPosition();
        position.set( ent.origin, ent.angles );

        if ( ref.team == TEAM_SPECTATOR )
        {
            position.skipWeapons = true;
        }
        else
        {
            position.skipWeapons = false;
            for ( int i = WEAP_NONE + 1; i < WEAP_TOTAL; i++ )
            {
                position.weapons[i] = ref.canSelectWeapon( i );
                Item @item = G_GetItem( i );
                position.ammos[i] = ref.inventoryCount( item.ammoTag );
            }
            position.weapon = ent.moveType == MOVETYPE_NOCLIP ? this.noclipWeapon : ref.weapon;
        }
        this.setQuickMenu();

        return true;
    }

    bool clearPosition()
    {
        if ( !this.practicing && this.client.team != TEAM_SPECTATOR && !this.preRace() )
        {
            G_PrintMsg( this.client.getEnt(), "Position clearing is not available during a race.\n" );
            return false;
        }

        this.savedPosition().clear();
        this.setQuickMenu();

        return true;
    }

    uint timeStamp()
    {
        return this.client.uCmdTimeStamp;
    }

    bool startRace()
    {
        if ( !this.preRace() )
            return false;

        if ( RS_QueryPjState( this.client.playerNum )  )
        {
          this.client.addAward( S_COLOR_RED + "Prejumped!" );
          this.client.respawn( false );
          RS_ResetPjState( this.client.playerNum );
          return false;
        }

        this.currentSector = 0;
        this.inRace = true;
        this.startTime = this.timeStamp();

        for ( int i = 0; i < numCheckpoints; i++ )
            this.sectorTimes[i] = 0;

        this.report.reset();

        this.client.newRaceRun( numCheckpoints );

        this.setQuickMenu();

        return true;
    }

    bool validTime()
    {
        return this.timeStamp() >= this.startTime;
    }

    uint raceTime()
    {
        return this.timeStamp() - this.startTime;
    }

    void cancelRace()
    {
        if ( this.inRace && this.currentSector > 0 )
        {
            Entity @ent = this.client.getEnt();
            uint rows = this.report.numRows();
            for ( uint i = 0; i < rows; i++ )
                G_PrintMsg( ent, this.report.getRow( i ) + "\n" );
            G_PrintMsg( ent, S_COLOR_ORANGE + "Race cancelled\n" );
        }

        this.inRace = false;
        this.postRace = false;
        this.finishTime = 0;
    }

    void completeRace()
    {
        uint delta;
        String str;

        if ( !this.validTime() ) // something is very wrong here
            return;

        this.client.addAward( S_COLOR_CYAN + "Race Finished!" );

        this.finishTime = this.raceTime();
        this.inRace = false;
        this.postRace = true;

        // send the final time to MM
        this.client.setRaceTime( -1, this.finishTime );

        str = "Current: " + RACE_TimeToString( this.finishTime );

        for ( int i = 0; i < MAX_RECORDS; i++ )
        {
            if ( !levelRecords[i].saved )
                break;
            if ( this.finishTime <= levelRecords[i].finishTime )
            {
                str += " (" + S_COLOR_GREEN + "#" + ( i + 1 ) + S_COLOR_WHITE + ")"; // extra id when on server record beating time
                break;
            }
        }

        Entity @ent = this.client.getEnt();

        G_CenterPrintMsg( ent, str + "\n" + RACE_TimeDiffString( this.finishTime, this.bestFinishTime, true ) );


        Client@[] specs = RACE_GetSpectators(this.client);
        for ( uint i = 0; i < specs.length; i++ )
        {
          Player@ spec_player = @RACE_GetPlayer(specs[i]);
          String line1 = "";
          String line2 = "";

          if ( this.hasTime )
          {
            line1 += "\u00A0   Current: " + RACE_TimeToString( this.finishTime ) + "   \u00A0";
            line2 += "\u00A0           " + RACE_TimeDiffString(this.finishTime, this.bestFinishTime, true) + "           \u00A0";
          } else {
            line1 += "\u00A0   Current: " + RACE_TimeToString( this.finishTime ) + "   \u00A0";
            line2 += "\u00A0           " + "                    " + "           \u00A0";
          }

          if ( spec_player.hasTime )
          {
            line1 = "\u00A0  Personal:    " + "          " + line1;
            line2 = RACE_TimeDiffString(this.finishTime, spec_player.bestFinishTime, true) + "          " + line2;
          } else if ( levelRecords[0].finishTime != 0 ) {
            line1 = "\u00A0                                " + line1;
            line2 = "\u00A0                                " + line2;
          }

          if ( levelRecords[0].finishTime != 0 )
          {
            line1 += "\u00A0          " + "Server:     \u00A0";
            line2 += "\u00A0      " + RACE_TimeDiffString(this.finishTime, levelRecords[0].finishTime, true) + "\u00A0";
          }

          G_CenterPrintMsg(specs[i].getEnt(), line1 + "\n" + line2);
        }

        //G_CenterPrintMsg( ent, str + "\n" + RACE_TimeDiffString( this.finishTime, this.bestFinishTime, true ) );
        this.report.addCell( "Race finished:" );
        this.report.addCell( RACE_TimeToString( this.finishTime ) );
        this.report.addCell( "Personal:" );
        this.report.addCell( RACE_TimeDiffString( this.finishTime, this.bestFinishTime, false ) );
        this.report.addCell( "Server:" );
        this.report.addCell( RACE_TimeDiffString( this.finishTime, levelRecords[0].finishTime, false ) );
        uint rows = this.report.numRows();
        for ( uint i = 0; i < rows; i++ )
            G_PrintMsg( ent, this.report.getRow( i ) + "\n" );

        if ( !this.hasTime || this.finishTime < this.bestFinishTime )
        {
            this.client.addAward( S_COLOR_YELLOW + "Personal record!" );
            // copy all the sectors into the new personal record backup
            this.setBestTime( this.finishTime );
            for ( int i = 0; i < numCheckpoints; i++ )
                this.bestSectorTimes[i] = this.sectorTimes[i];
        }

        // see if the player improved one of the top scores
        for ( int top = 0; top < MAX_RECORDS; top++ )
        {
            if ( !levelRecords[top].saved || this.finishTime < levelRecords[top].finishTime )
            {
                String cleanName = this.client.name.removeColorTokens().tolower();
                String login = this.client.getMMLogin();

                if ( top == 0 )
                {
                    this.client.addAward( S_COLOR_GREEN + "Server record!" );
                    if ( levelRecords[0].finishTime == 0 )
                      G_PrintMsg( null, this.client.name + S_COLOR_YELLOW + " set a new ^2livesow.net ^3record: "
                              + S_COLOR_GREEN + RACE_TimeToString( this.finishTime ) + "\n" );
                    else
                      G_PrintMsg( null, this.client.name + S_COLOR_YELLOW + " set a new ^2livesow.net ^3record: "
                              + S_COLOR_GREEN + RACE_TimeToString( this.finishTime ) + " " + S_COLOR_YELLOW + "[-" + RACE_TimeToString( levelRecords[0].finishTime - this.finishTime ) + "]\n" );
                }

                int remove = MAX_RECORDS - 1;
                for ( int i = 0; i < MAX_RECORDS; i++ )
                {
                    if ( ( login == "" && levelRecords[i].login == "" && levelRecords[i].playerName.removeColorTokens().tolower() == cleanName )
                            || ( login != "" && levelRecords[i].login == login ) )
                    {
                        if ( i < top )
                            remove = -1; // he already has a better time, don't save it
                        else
                            remove = i;
                        break;
                    }
                    if ( login == "" && levelRecords[i].login != "" && levelRecords[i].playerName.removeColorTokens().tolower() == cleanName && i < top )
                    {
                        remove = -1; // he already has a better time, don't save it
                        break;
                    }
                }

                if ( remove != -1 )
                {
                    // move the other records down
                    for ( int i = remove; i > top; i-- )
                        levelRecords[i].Copy( levelRecords[i - 1] );

                    levelRecords[top].Store( this.client );

                    if ( login != "" )
                    {
                        // there may be authed and unauthed records for a
                        // player; remove the unauthed if it is worse than the
                        // authed one
                        bool found = false;
                        for ( int i = top + 1; i < MAX_RECORDS; i++ )
                        {
                            if ( levelRecords[i].login == "" && levelRecords[i].playerName.removeColorTokens().tolower() == cleanName )
                                found = true;
                            if ( found && i < MAX_RECORDS - 1 )
                                levelRecords[i].Copy( levelRecords[i + 1] );
                        }
                        if ( found )
                            levelRecords[MAX_RECORDS - 1].clear();
                    }

                    RACE_WriteTopScores();
                    RACE_UpdateHUDTopScores();
                }

                break;
            }
        }

        // set up for respawning the player with a delay
        Entity @respawner = G_SpawnEntity( "race_respawner" );
        respawner.nextThink = levelTime + 5000;
        @respawner.think = race_respawner_think;
        respawner.count = this.client.playerNum;

        G_AnnouncerSound( this.client, G_SoundIndex( "sounds/misc/timer_ploink" ), GS_MAX_TEAMS, false, null );
    }

    bool touchCheckPoint( int id )
    {
        uint delta;
        String str;

        if ( id < 0 || id >= numCheckpoints )
            return false;

        if ( !this.inRace )
            return false;

        if ( this.sectorTimes[id] != 0 ) // already past this checkPoint
            return false;

        if ( !this.validTime() ) // something is very wrong here
            return false;

        this.sectorTimes[id] = this.raceTime();

        // send this checkpoint to MM
        this.client.setRaceTime( id, this.sectorTimes[id] );

        // print some output and give awards if earned

        str = "Current: " + RACE_TimeToString( this.sectorTimes[id] );

        for ( int i = 0; i < MAX_RECORDS; i++ )
        {
            if ( this.sectorTimes[id] <= levelRecords[i].sectorTimes[id] )
            {
                str += " (" + S_COLOR_GREEN + "#" + ( i + 1 ) + S_COLOR_WHITE + ")"; // extra id when on server record beating time
                break;
            }
        }

        Entity @ent = this.client.getEnt();

        G_CenterPrintMsg( ent, str + "\n" + RACE_TimeDiffString( this.sectorTimes[id], this.bestSectorTimes[id], true ) );


        Client@[] specs = RACE_GetSpectators(this.client);
        for ( uint i = 0; i < specs.length; i++ )
        {
          Player@ spec_player = @RACE_GetPlayer(specs[i]);
          String line1 = "";
          String line2 = "";

          if ( this.hasTime && this.sectorTimes[id] != 0 )
          {
            line1 += "\u00A0   Current: " + RACE_TimeToString( this.sectorTimes[id] ) + "   \u00A0";
            line2 += "\u00A0           " + RACE_TimeDiffString(this.sectorTimes[id], this.bestSectorTimes[id], true) + "           \u00A0";
          } else {
            line1 += "\u00A0   Current: " + RACE_TimeToString( this.sectorTimes[id] ) + "   \u00A0";
            line2 += "\u00A0           " + "                    " + "           \u00A0";
          }

          if ( spec_player.hasTime && spec_player.bestSectorTimes[id] != 0 )
          {
            line1 = "\u00A0  Personal:    " + "          " + line1;
            line2 = RACE_TimeDiffString(this.sectorTimes[id], spec_player.bestSectorTimes[id], true) + "          " + line2;
          } else if ( levelRecords[0].finishTime != 0 ) {
            line1 = "\u00A0                                " + line1;
            line2 = "\u00A0                                " + line2;
          }

          if ( levelRecords[0].finishTime != 0 && levelRecords[0].sectorTimes[id] != 0 )
          {
            line1 += "\u00A0          " + "Server:     \u00A0";
            line2 += "\u00A0      " + RACE_TimeDiffString(this.sectorTimes[id], levelRecords[0].sectorTimes[id], true) + "\u00A0";
          }

          G_CenterPrintMsg(specs[i].getEnt(), line1 + "\n" + line2);
        }

        //G_CenterPrintMsg( ent, str + "\n" + RACE_TimeDiffString( this.sectorTimes[id], this.bestSectorTimes[id], true ) );
        this.report.addCell( "Sector " + this.currentSector + ":" );
        this.report.addCell( RACE_TimeToString( this.sectorTimes[id] ) );
        this.report.addCell( "Personal:" );
        this.report.addCell( RACE_TimeDiffString( this.sectorTimes[id], this.bestSectorTimes[id], false ) );
        this.report.addCell( "Server:" );
        this.report.addCell( RACE_TimeDiffString( this.sectorTimes[id], levelRecords[0].sectorTimes[id], false ) );

        // if beating the level record on this sector give an award
        if ( this.sectorTimes[id] < levelRecords[0].sectorTimes[id] )
        {
            this.client.addAward( "Sector record on sector " + this.currentSector + "!" );
        }
        // if beating his own record on this sector give an award
        else if ( this.sectorTimes[id] < this.bestSectorTimes[id] )
        {
            // ch : does racesow apply sector records only if race is completed?
            this.client.addAward( "Personal record on sector " + this.currentSector + "!" );
            //this.bestSectorTimes[id] = this.sectorTimes[id];
        }

        this.currentSector++;

        G_AnnouncerSound( this.client, G_SoundIndex( "sounds/misc/timer_bip_bip" ), GS_MAX_TEAMS, false, null );

        return true;
    }

    void enterPracticeMode()
    {
        if ( this.practicing )
            return;

        this.practicing = true;
        G_CenterPrintMsg( this.client.getEnt(), S_COLOR_CYAN + "Entered practice mode" );
        // msc: practicemode message
        client.setHelpMessage(practiceModeMsg);
        this.cancelRace();
        this.setQuickMenu();
    }

    void leavePracticeMode()
    {
        if ( !this.practicing )
            return;

        this.practicing = false;
        G_CenterPrintMsg( this.client.getEnt(), S_COLOR_CYAN + "Left practice mode" );
        // msc: practicemode message
        client.setHelpMessage(defaultMsg);
        if ( this.client.team != TEAM_SPECTATOR )
            this.client.respawn( false );
        this.setQuickMenu();
    }

    void togglePracticeMode()
    {
        if ( pending_endmatch )
            this.client.printMessage("Can't join practicemode in overtime.\n");
        else if ( this.practicing )
            this.leavePracticeMode();
        else
            this.enterPracticeMode();
    }
}

Player @RACE_GetPlayer( Client @client )
{
    if ( @client == null || client.playerNum < 0 )
        return null;

    Player @player = players[client.playerNum];
    @player.client = client;

    return player;
}

// the player has finished the race. This entity times his automatic respawning
void race_respawner_think( Entity @respawner )
{
    Client @client = G_GetClient( respawner.count );

    // the client may have respawned on their own, so check if they are in postRace
    if ( RACE_GetPlayer( client ).postRace && client.team != TEAM_SPECTATOR )
        client.respawn( false );

    respawner.freeEntity(); // free the respawner
}
