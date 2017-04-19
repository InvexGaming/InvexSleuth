#if defined _convertsteamid_included
 #endinput
#endif
#define _convertsteamid_included

//Given a steamid64, returns steamid2
//Always uses the '1' prefix for the universe
stock void GetSteamId2(const char[] szSteam64, char[] szSteam2, int iLen)
{
  char szBase[18] = "76561197960265728";
  int iBorrow = 0;
  char szSteam[18];
  char szAccount[18];
  int iY = 0;
  int iZ = 0;
  int iTemp = 0;
  
  //Copy steamid64 Over
  Format(szSteam, sizeof(szSteam), szSteam64);
  
  //Determine iY
  if (intval(szSteam[16]) % 2 == 1) {
    iY = 1;
    szSteam[16] = strval(intval(szSteam[16]) - 1);
  }
  
  //Determine szAccount
  for (int k = 16; k >= 0; --k) {
    if (iBorrow > 0) {
      iTemp = intval(szSteam[k]) - 1;
      
      if (iTemp >= intval(szBase[k])) {
        iBorrow = 0;
        szAccount[k] = strval(iTemp - intval(szBase[k]));
      }
      else {
        iBorrow = 1;
        szAccount[k] = strval((iTemp + 10) - intval(szBase[k]));
      }
    }
    else {
      if (intval(szSteam[k]) >= intval(szBase[k])) {
        iBorrow = 0;
        szAccount[k] = strval(intval(szSteam[k]) - intval(szBase[k]));
      }
      else {
        iBorrow = 1;
        szAccount[k] = strval((intval(szSteam[k]) + 10) - intval(szBase[k]));
      }
    }
  }
  
  //Divide szAccount answer by 2
  iZ = StringToInt(szAccount) / 2;
  
  //Construct final steam2 id
  Format(szSteam2, iLen, "STEAM_1:%d:%d", iY, iZ);
}

int strval(const int iNum)
{
  return '0' + ((iNum >= 0 && iNum <= 9) ? iNum : 0);
}

int intval(int cNum)
{
  return (cNum >= '0' && cNum <= '9') ? (cNum - '0') : 0;
}