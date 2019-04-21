Client@[] RACE_GetSpectators( Client@ client )
{
  Client@[] speclist;

  for ( int i = 0; i < maxClients; i++ )
  {
    Client@ specClient = @G_GetClient(i);

    if ( specClient.chaseActive && specClient.chaseTarget == client.getEnt().entNum )
    {
      speclist.push_back(@specClient);
    }
  }
  return speclist;
}

bool Pending_AnyRacing(bool respawn = false)
{
  bool any_racing = false;
  for ( int i = 0; i < maxClients; i++ )
  {
    Client @client = G_GetClient( i );
    if ( client.state() < CS_SPAWNED )
        continue;

    Player@ player = RACE_GetPlayer( client );
    if ( player.inRace && !player.postRace && client.team != TEAM_SPECTATOR )
    {
      any_racing = true;
    } else {
      if ( client.team != TEAM_SPECTATOR )
      {
        client.team = TEAM_SPECTATOR;
        if ( respawn )
          client.respawn( false );
      }
    }
  }
  return any_racing;
}

String RACE_TimeToString( uint time )
{
    // convert times to printable form
    String minsString, secsString, millString;
    uint min, sec, milli;

    milli = time;
    min = milli / 60000;
    milli -= min * 60000;
    sec = milli / 1000;
    milli -= sec * 1000;

    if ( min == 0 )
        minsString = "00";
    else if ( min < 10 )
        minsString = "0" + min;
    else
        minsString = min;

    if ( sec == 0 )
        secsString = "00";
    else if ( sec < 10 )
        secsString = "0" + sec;
    else
        secsString = sec;

    if ( milli == 0 )
        millString = "000";
    else if ( milli < 10 )
        millString = "00" + milli;
    else if ( milli < 100 )
        millString = "0" + milli;
    else
        millString = milli;

    return minsString + ":" + secsString + "." + millString;
}

String RACE_TimeDiffString( uint time, uint reference, bool clean )
{
    if ( reference == 0 && clean )
        return "";
    else if ( reference == 0 )
        return S_COLOR_WHITE + "--:--.---";
    else if ( time == reference )
        return S_COLOR_YELLOW + "+-" + RACE_TimeToString( 0 );
    else if ( time < reference )
        return S_COLOR_GREEN + "-" + RACE_TimeToString( reference - time );
    else
        return S_COLOR_RED + "+" + RACE_TimeToString( time - reference );
}

void RACE_UpdateHUDTopScores()
{
    for ( int i = 0; i < HUD_RECORDS; i++ )
    {
        G_ConfigString( CS_GENERAL + i, "" ); // somehow it is not shown the first time if it isn't initialized like this
        if ( levelRecords[i].saved && levelRecords[i].playerName.length() > 0 )
            G_ConfigString( CS_GENERAL + i, "#" + ( i + 1 ) + " - " + levelRecords[i].playerName + " - " + RACE_TimeToString( levelRecords[i].finishTime ) );
    }
}
