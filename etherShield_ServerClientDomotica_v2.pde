/*
 * Arduino ENC28J60 Ethernet shield twitter client
 */
 
#define MAXTEMP 0
#define MINTEMP 1

#define MINMAIL 2
#define MINTWITTER 3
#define MINKYROS 4

#define MAXMAIL 5
#define MAXTWITTER 6
#define MAXKYROS 7

#define PRESENCIAMAIL 8
#define PRESENCIATWITTER 8
#define PRESENCIAKYROS 8

#include "etherShield.h"
#include <avr/wdt.h>
#include <EEPROM.h>

// A pin to use as input to trigger tweets
#define INPUT_PIN 0
#define PANIC_PIN 1
#define LED_PIN 2
int temp_pin = A0;
int LedState = 0;
int sentAlarm = 0;

int tempC = 0;
int tempCmin = 99;
int tempCmax = 0;

int MaxTemp = 22;
int MinTemp = 18;

int MinMail = 1;
int MinTwitter = 1;
int MinKyros = 0;

int MaxMail = 0;
int MaxTwitter = 0;
int MaxKyros = 0;

int PresenciaMail = 1;
int PresenciaTwitter = 1;
int PresenciaKyros = 1;

// Note: This software implements a web server and a web browser.
// The web server is at "myip" 
// 
// Please modify the following lines. mac and ip have to be unique
// in your local area network. You can not have the same numbers in
// two devices:
// how did I get the mac addr? Translate the first 3 numbers into ascii is: TUX
static uint8_t mymac[6] = {
  0x54,0x55,0x58,0x10,0x00,0x25};

static uint8_t myip[4] = {
  192,168,1,32};
  
// IP address of the twitter server to contact (IP of the first portion of the URL):
// DNS look-up is a feature which we still need to add.
static uint8_t websrvip[4] = {
  217,160,250,56};
  
#define WEBSERVER_VHOST "www.iagodiaz.com"
// Default gateway. The ip address of your DSL router. It can be set to the same as
// websrvip the case where there is no default GW to access the 
// web server (=web server is on the same lan as this host) 
static uint8_t gwip[4] = {
  192,168,1,1};  
  
// listen port for tcp/www:
#define MYWWWPORT 80
static uint16_t dest_port=80;  

// global string buffer for twitter message:
static char statusstr[150];

// the password string, (only a-z,0-9,_ characters):
static char password[]="secret"; 

static volatile uint8_t start_web_client=0;  // 0=off but enabled, 1=send tweet, 2=sending initiated, 3=twitter was sent OK, 4=diable twitter notify
static uint8_t contact_onoff_cnt=0;
static uint8_t web_client_attempts=0;
static uint8_t web_client_sendok=0;
static uint8_t resend=0;

int buttonState;             // the current reading from the input pin
int lastButtonState = LOW;   // the previous reading from the input pin

int buttonPanicState;             // the current reading from the input pin
int lastButtonPanicState = LOW;   // the previous reading from the input pin

// the follow variables are longs because the time, measured in milliseconds,
// will quickly become a bigger number than can be stored in an int.
long lastDebounceTime = 0;  // the last time the output pin was toggled
long debounceDelay = 200;   // the debounce time, increase if the output flickers

long lastDebouncePanicTime = 0;  // the last time the output pin was toggled
long debouncePanicDelay = 200;   // the debounce time, increase if the output flickers

#define BUFFER_SIZE 1250
#define DATE_BUFFER_SIZE 30
static char datebuf[DATE_BUFFER_SIZE]="none";
static uint8_t buf[BUFFER_SIZE+1];

EtherShield es=EtherShield();

uint8_t verify_password(char *str)
{
  // the first characters of the received string are
  // a simple password/cookie:
  if (strncmp(password,str,strlen(password))==0){
    return(1);
  }
  return(0);
}

// analyse the url given
// return values: -1 invalid password
//                -2 no command given 
//                0 switch off
//                1 switch on
//
//                The string passed to this function will look like this:
//                /?mn=1&pw=secret HTTP/1.....
//                / HTTP/1.....
int8_t analyse_get_url(char *str)
{
  uint8_t mn=0;
  char kvalstrbuf[10];
  // the first slash:
  if (str[0] == '/' && str[1] == ' '){
    // end of url, display just the web page
    return(2);
  }

  if (es.ES_find_key_val(str,kvalstrbuf,10,"pw")){
      if (verify_password(kvalstrbuf)){
        int address = 0;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"valor0")){ int valor; valor = atoi(kvalstrbuf); MinTemp = valor; EEPROM.write(MINTEMP, valor);}
        address++; 
        if(es.ES_find_key_val(str,kvalstrbuf,10,"valor1")){ int valor; valor = atoi(kvalstrbuf); MaxTemp = valor; EEPROM.write(MAXTEMP, valor);}
        address++; 
        if(es.ES_find_key_val(str,kvalstrbuf,10,"mail0")) { MinMail = 1; EEPROM.write(2, 1); } else { MinMail = 0; EEPROM.write(2, 0); }
        address++;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"twitter0")) { MinTwitter = 1; EEPROM.write(3, 1); } else { MinTwitter = 0; EEPROM.write(3, 0); }
        address++;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"kyros0")) { MinKyros = 1; EEPROM.write(4, 1); } else { MinKyros = 0; EEPROM.write(4, 0); }
        address++;

        if(es.ES_find_key_val(str,kvalstrbuf,10,"mail1")) { MaxMail = 1; EEPROM.write(5, 1); } else { MaxMail = 0; EEPROM.write(5, 0); }
        address++;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"twitter1")) { MaxTwitter = 1; EEPROM.write(6, 1); } else { MaxTwitter = 0; EEPROM.write(6, 0); }
        address++;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"kyros1")) { MaxKyros = 1; EEPROM.write(7, 1); } else { MaxKyros = 0; EEPROM.write(7, 0); }
        address++;
        
        if(es.ES_find_key_val(str,kvalstrbuf,10,"mail2")) { PresenciaMail = 1; EEPROM.write(8, 1); } else { PresenciaMail = 0; EEPROM.write(8, 0); }
        address++;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"twitter2")) { PresenciaTwitter = 1; EEPROM.write(9, 1); } else { PresenciaTwitter = 0; EEPROM.write(9, 0); }
        address++;
        if(es.ES_find_key_val(str,kvalstrbuf,10,"kyros2")) { PresenciaKyros = 1; EEPROM.write(10, 1); } else { PresenciaKyros = 0; EEPROM.write(10, 0); }
        address++;
        
        if (es.ES_find_key_val(str,kvalstrbuf,10,"p0")){
          mn = kvalstrbuf[0]=='1';
          EEPROM.write(11, mn);
          return(mn);
        }
      }
      else{
        return(-1);
      }
  }
  
  // browsers looking for /favion.ico, non existing pages etc...
  return(-1);
}

uint16_t http200ok(void)
{
  return(es.ES_fill_tcp_data_p(buf,0,PSTR("HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nPragma: no-cache\r\n\r\n")));
}

// prepare the webpage by writing the data to the tcp send buffer
uint16_t print_webpage(uint8_t *buf)
{
  uint16_t plen;
  char vstr[5];
  plen=http200ok();
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<?xml version='1.0'?><domotica><temperatura><estancia>salon</estancia><valor>"));
  itoa(tempC,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</valor></temperatura><temperatura><estancia>salon (min)</estancia><valor>"));
  itoa(tempCmin,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</valor></temperatura><temperatura><estancia>salon (max)</estancia><valor>"));
  itoa(tempCmax,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</valor></temperatura>"));
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<alarma><tipo>Temperatura baja</tipo><mail>"));
  itoa(MinMail,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</mail><twitter>"));
  itoa(MinTwitter,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</twitter><kyros>"));
  itoa(MinKyros,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</kyros><valor>"));
  itoa(MinTemp,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</valor></alarma>"));
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<alarma><tipo>Temperatura alta</tipo><mail>"));
  itoa(MaxMail,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</mail><twitter>"));
  itoa(MaxTwitter,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</twitter><kyros>"));
  itoa(MaxKyros,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</kyros><valor>"));
  itoa(MaxTemp,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</valor></alarma>"));
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<alarma><tipo>Presencia</tipo><mail>"));
  itoa(PresenciaMail,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</mail><twitter>"));
  itoa(PresenciaTwitter,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</twitter><kyros>"));
  itoa(PresenciaKyros,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</kyros><valor>-</valor></alarma>"));
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<actuador><tipo>LED</tipo><valor>"));
  itoa(LedState,vstr,10);
  plen=es.ES_fill_tcp_data(buf,plen,vstr);
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("</valor></actuador></domotica>"));
  return(plen);
}

// prepare the webpage by writing the data to the tcp send buffer
uint16_t print_redirectpage(uint8_t *buf)
{
  uint16_t plen;
  char vstr[5];
  plen=http200ok();
  
  plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<script> parent.location.href = 'http://www.iagodiaz.com/domotica'; </script>"));
  //cambiar
  //plen=es.ES_fill_tcp_data_p(buf,plen,PSTR("<script> parent.location.href = 'http://172.26.0.146/domotica/mobile.php'; </script>"));

  return(plen);
}

void store_date_if_found(char *str)
{
  uint8_t i=100; // search the first 100 char
  uint8_t j=0;
  char datekeyword[]="Date: "; // not any repeating characters, search does not need to resume at partial match
  while(i && *str){
    if (j && datekeyword[j]=='\0'){
      // found date
      i=0;
      while(*str && *str!='\r' && *str!='\n' && i< DATE_BUFFER_SIZE-1){
        datebuf[i]=*str;
        str++;
        i++;
      }
      datebuf[i]='\0';
      return;
    }
    if (*str==datekeyword[j]){
      j++;
    }
    else{
      j=0;
    }
    str++;
    i--;
  }
}

void browserresult_callback(uint8_t statuscode,uint16_t datapos){
  if (statuscode==0){
    web_client_sendok++;
    //    LEDOFF;
    // copy the "Date: ...." as returned by the server
    store_date_if_found((char *)&(buf[datapos]));
  }
  // clear pending state at sucessful contact with the
  // web server even if account is expired:
  if (start_web_client==2) start_web_client=3;
}


void setup(){
  Serial.begin(9600);
  Serial.println("Setup");
  int address = 0;
  MaxTemp = EEPROM.read(address++);
  MinTemp = EEPROM.read(address++);

  MinMail = EEPROM.read(address++);
  MinTwitter = EEPROM.read(address++);
  MinKyros = EEPROM.read(address++);

  MaxMail = EEPROM.read(address++);
  MaxTwitter = EEPROM.read(address++);
  MaxKyros = EEPROM.read(address++);

  PresenciaMail = EEPROM.read(address++);
  PresenciaTwitter = EEPROM.read(address++);
  PresenciaKyros = EEPROM.read(address++);
  
  LedState = EEPROM.read(address);
  
  Serial.println("Variables cargadas");

  pinMode( INPUT_PIN, INPUT );
  digitalWrite( INPUT_PIN, HIGH );    // Set internal pullup
  
  pinMode( PANIC_PIN, INPUT );
  digitalWrite( PANIC_PIN, HIGH );    // Set internal pullup

  pinMode( LED_PIN, OUTPUT );
  digitalWrite( LED_PIN, LedState);    // Set internal pullup

  /*initialize enc28j60*/
  es.ES_enc28j60Init(mymac);

  //init the ethernet/ip layer:
  es.ES_init_ip_arp_udp_tcp(mymac,myip, MYWWWPORT);

  // init the web client:
  es.ES_client_set_gwip(gwip);  // e.g internal IP of dsl router
  es.ES_client_set_wwwip(websrvip);

  Serial.println("Arrancado");
  wdt_disable();
  wdt_enable(WDTO_8S);

}

void loop(){
  uint16_t dat_p;
  int8_t cmd;
  start_web_client=0;

  uint16_t contador = 0;
  uint16_t contador2 = 0;
  
  char getURL[100];
  int pos = 0;

  while(1){
    wdt_reset();
    if(++contador == 65535) {
        //if(++contador2 == 1) {
        tempC = get_temp();
        tempC = (3.3 * tempC * 100.0)/1024.0;
        Serial.println(tempC);
        if(tempC > tempCmax) {
          tempCmax = tempC;
        }
        if(tempC < tempCmin) {
          tempCmin = tempC;
        }
        if( ((tempC > MaxTemp && sentAlarm == 0) || (tempC < MinTemp && sentAlarm == 0))
             &&  (((MinMail==1)||(MaxMail==1)) || ((MinKyros==1)||(MaxKyros==1)))
        ) {
            start_web_client=1;
            sentAlarm = 1;
            int pos = 0;
            
            if ((MinMail==1)||(MaxMail==1)) {
              strncpy(getURL, "temp=", 5);
              char var[5];
              itoa(tempC, var, 10);
              strncpy(getURL + 5,var,2);
              pos = 7;
            }
            if ((MinTwitter==1)||(MaxTwitter==1)) {
              strncpy(getURL + pos, "&twitter=1", 10);
              pos = pos + 10;
            }
            
            strncpy(getURL + pos,"\0",1);
            Serial.println(getURL);
        }
        if((tempC < MaxTemp + 1) && (tempC > MinTemp - 1)) {
            sentAlarm = 0;
            Serial.println("Reset");
        }   
         //AÃ±adir &twitter=1 si procede!!!     
      contador = 0;
    }
    
    // handle ping and wait for a tcp packet
    dat_p=es.ES_packetloop_icmp_tcp(buf,es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf));
    if(dat_p==0){
      if (start_web_client==1){
        Serial.println("A mandar!");
        start_web_client=2;
        web_client_attempts++;
        es.ES_client_send_message(getURL, &browserresult_callback, 80);
        //es.ES_client_browse_url(PSTR("/domotica/alerta.php?presencia=1"), "", PSTR(WEBSERVER_VHOST), &browserresult_callback, 80);
      }
      else if (start_web_client==7){

      }
      buttonState = digitalRead(INPUT_PIN);
      buttonPanicState = digitalRead(PANIC_PIN);
      // check to see if you just pressed the button 
      // (i.e. the input went from HIGH to LOW),  and you've waited 
      // long enough since the last press to ignore any noise:  
      if(start_web_client!=4) {
        if ((buttonState == LOW) && 
          (lastButtonState == HIGH) && 
          (millis() - lastDebounceTime) > debounceDelay) {
          contact_onoff_cnt++;
          // ... and store the time of the last button press
          // in a variable:
          lastDebounceTime = millis();
  
          // Trigger a tweet        
          resend=1; // resend once if it failed
          start_web_client=1;
  
        }
        
        if ((buttonPanicState == LOW) && 
          (lastButtonPanicState == HIGH) && 
          (millis() - lastDebouncePanicTime) > debouncePanicDelay) {
          //contact_onoff_cnt++;
          // ... and store the time of the last button press
          // in a variable:
          lastDebouncePanicTime = millis();
  
          // Trigger a tweet        
          resend=1; // resend once if it failed
          start_web_client=7;
  
        }
        lastButtonPanicState = buttonPanicState;
  
        // save the buttonState.  Next time through the loop,
        // it'll be the lastButtonState:
        lastButtonState = buttonState;
      }
      
      continue;
    }

    if (strncmp("GET ",(char *)&(buf[dat_p]),4)!=0){
      // head, post and other methods:
      //
      // for possible status codes see:
      // http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
      dat_p=http200ok();
      dat_p=es.ES_fill_tcp_data_p(buf,dat_p,PSTR("<h1>200 OK</h1>"));
      goto SENDTCP;
    }
    cmd=analyse_get_url((char *)&(buf[dat_p+4]));
    // for possible status codes see:
    // http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
    if (cmd==-1){
      dat_p=es.ES_fill_tcp_data_p(buf,0,PSTR("HTTP/1.0 401 Unauthorized\r\nContent-Type: text/html\r\n\r\n<h1>401 Unauthorized</h1>"));
      goto SENDTCP;
    }
    
    if(cmd==1)
    {
      digitalWrite(LED_PIN, HIGH);
      LedState = 1;
    }
    else if(cmd==0)
    {
      digitalWrite(LED_PIN, LOW);
      LedState = 0;
    }
    /*
    if (cmd==1 && start_web_client==4){
      // twitter was off, switch on
      start_web_client=0;
    }
    if (cmd==0 ){
      start_web_client=4; // twitter off
    }*/
    dat_p=http200ok();
    if(cmd == 2)
      dat_p=print_webpage(buf);
    else
      dat_p=print_redirectpage(buf);
    //
SENDTCP:
    es.ES_www_server_reply(buf,dat_p); // send data

  }

}

int get_temp() {
  uint16_t currentTemp = 0;
  for(int i=0;i<8;i++){
    currentTemp = currentTemp + analogRead(A0);
  }
  currentTemp = currentTemp/8;
  return (int)currentTemp;
}


