#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <argp.h>
#include <sys/types.h>
#include <sys/stat.h>

/*
  Simple program to read configuration of U-Blox GPS serial port.
  Based on: https://gist.github.com/SlightlyLoony/9493869d31b76cb4d81aba302d00f782
  with additional changes from https://ava.upuaut.net/?p=951
*/

#define DEBUG(...) do { \
	if(arguments.debug>0) { printf(__VA_ARGS__); } \
	} while(0)


/////  begin ARGP stuff

const char *argp_program_version = "ubloxcfg 0.1";
const char *argp_program_bug_address = "<tom@dilatush.com>";
static char doc[] = "ubloxcfg - configure U-Blox GPS";

int option = 0;

/* A description of the arguments we accept. */
static char args_doc[] = "";

/* The options we understand. */
static struct argp_option options[] = {
  { "baud",   'b', 0, 0, "Check baud rate of GPS"                     },
  { "read",   'r', 0, 0, "Read port configuration"                    },
  { "echo",   'e', 0, 0, "Echo GPS output to console"                 },
  { "quiet",  'q', 0, 0, "Quiet mode (fewer messages)"                },
  { "toggle", 't', 0, 0, "Toggle baud rate between 9,600 and 115,200" },
  { "high",   'h', 0, 0, "Try synchronizing at 115,200 baud first"    },
  { "debug",  'D', 0, 0, "Enable some debugging messages"             },
  { "device", 'd', "FILE", 0, "Serial device name of GPS"             },
  { 0 }
};

/* Used by main to communicate with parse_opt. */
struct arguments {
  int baudCheck;
  int readPortCfg;
  int toggle;
  int echo;
  int quiet;
  int high;
  int debug;
  char *device;
};

struct arguments arguments;



/* Parse a single option. */
static error_t parse_opt (int key, char *arg, struct argp_state *state) {
  /* Get the input argument from argp_parse, which we
     know is a pointer to our arguments structure. */
  struct arguments *arguments = state->input;

  switch (key) {

    case 'r': arguments->readPortCfg = 1;  break;
    case 'b': arguments->baudCheck = 1;    break;
    case 'q': arguments->quiet = 1;        break;
    case 't': arguments->toggle = 1;       break;
    case 'e': arguments->echo = 1;         break;
    case 'h': arguments->high = 1;         break;
    case 'D': arguments->debug = 1;        break;
    case 'd': arguments->device=arg;	   break;

   case ARGP_KEY_END:
      if( arguments->baudCheck + arguments->readPortCfg + arguments->echo 
          + arguments->toggle  == 0 )
	      argp_usage(state);
      break;

    default:
      return ARGP_ERR_UNKNOWN;
  }
  return 0;
}

/* Our argp parser. */
static struct argp argp = { options, parse_opt, args_doc, doc };

/////  end ARGP stuff


typedef struct ubxMsg {
	int size;
	unsigned char* msg;
	int noMsg;
	int valid;
	int class;
	int id;
	int bodySize;
	unsigned char* body;
} UBXMsg;

unsigned char portQueryBody[] = {
	0xB5, 0x62,             /* message header */ \
	0x06, 0x00,             /* message class and ID */  \
	0x01, 0x00,             /* message body length */  \
	0x01,                   /* UART ID */ \
	0x00, 0x00              /* checksum */ \
	};
unsigned char save[] = {0xB5, 0x62, 0x06, 0x09, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x1D, 0xAB};

UBXMsg createUbxMsg( unsigned char class, unsigned char id, unsigned char* body, int bodySize ) {
    UBXMsg result;
	result.msg = calloc( bodySize + 8, 1 );
	result.msg[0] = 0xB5;
	result.msg[1] = 0x62;
	result.msg[2] = class;
	result.msg[3] = id;
	result.msg[4] = bodySize & 0xFF;
	result.msg[5] = bodySize >> 8;
	memcpy( result.msg + 6, body, bodySize );
	
	// calculate Fletcher checksum for this message...
	unsigned char ck_a = 0;
	unsigned char ck_b = 0;
	int i;
	for( i = 2; i < bodySize + 6; i++ ) {
		ck_a += result.msg[i];
		ck_b += ck_a;
	}
	result.msg[bodySize + 6] = ck_a;
	result.msg[bodySize + 7] = ck_b;
	
	result.size = bodySize + 8;
	result.bodySize = bodySize;
	result.id = id;
	result.class = class;
	result.valid = 1;
	result.noMsg = 0;
	result.body = body;
	return result;
}

UBXMsg getPortQueryMsg() {
	unsigned char body[] = { 0x01 };
    return createUbxMsg( 0x06, 0x00, body, 1 );
}



// returns character if available, otherwise -1
int readUART( int fd ) {

	// Read a character from the port, if there is one
	unsigned char rx_buffer[1];
	int rx_length = read( fd, (void*)rx_buffer, 1 );		//Filestream, buffer to store in, number of bytes to read (max)
	if (rx_length < 0)
	{
		if( rx_length < -1 ) {
			printf( "Read error, %d\n", rx_length );
			return -2;
		}
		return -1;
	}
	else if (rx_length == 0)
	{
		//No data waiting
		return -1;
	}
	else
	{
		//Bytes received
		return rx_buffer[0];
	}
}


// echoes characters received from GPS onto console; never exits
void echo( int fd ) {
	while( 1 ) {
		usleep( 50 );
		int c = readUART( fd );
		if( c >= 0 ) printf( "%c", c );
	}
}


// waits up to five seconds for the given string to be read
// returns 0 for failure, 1 for success
int waitForString( int fd, char* str, int size ) {
	int attempts = 0;
	int gotIt = 0;
	int index = 0;
	while( (attempts < 100000) && (gotIt == 0) ) {
		usleep( 50 );
		int x = readUART( fd );
		if( x >= 0 ) {
			//printf("%c", x);
			if( x == str[index] ) {
				index++;
				if( index == size ) {
					gotIt = 1;
				}
			}
			else {
				index = 0;
			}
		}
		attempts++;
	}
	return gotIt;
}


// Waits up to five seconds for a known message ("$GNGGA") to appear,
// returning 1 if synchronized, 0 otherwise.
// this is needed because upon opening the port the UART's receiver may
// not be synchronized to the data stream, and will return garbage data.
// Once synchronized, it should stay synchronized.
int syncRx( int fd ) {
	return (waitForString( fd, "$GNGGA,", 7 ) == 0 ) ? 0 : 1;
}


void setTermOptions( int fd, int baud ) {

	struct termios options;
	tcgetattr( fd, &options );
	options.c_cflag = baud | CS8 | CLOCAL | CREAD;
	options.c_iflag = IGNPAR;
	options.c_oflag = 0;
	options.c_lflag = 0;
	tcflush( fd, TCIFLUSH );
	tcsetattr( fd, TCSANOW, &options );
}


// returns file descriptor or -1 if failure...
// hint is 1 to try 115,200 baud first
int openUART( char *device, int quiet, int hint ) {

	int fd = -1;
	DEBUG( "DEBUG: openUART(%s)\n", device);
	fd = open(device, O_RDWR | O_NOCTTY | O_NDELAY);		//Open in non blocking read/write mode

	if (fd == -1) {
		printf( "Can't open %s - possibly it's in use by another application\n", device );
		return fd;
	}
	
	// we try twice...
	DEBUG( "DEBUG: checking supported baudrates\n");
	int try = (hint ? B115200 : B9600);
	int i;
	for( i = 0; i < 2; i++ ) {
		setTermOptions( fd, try );
		if( syncRx( fd ) ) {
			char* baud = ((try == B9600) ? "9,600" : "115,200" );
			if( !quiet ) printf( "Synchronized at %s baud...\n", baud );
			return fd;
		}
		try = ((try == B9600) ? B115200 : B9600);
	}

	// we failed, so close the port...
	close( fd );
	DEBUG( "DEBUG: failed to synchronize baudrate\n");
	return -1;
}

// Waits up to five seconds for a UBX message to be received.
// Entire message is received, validated, and decoded.
// If no message is received, the noMsg flag will be set.
// If a valid message is received, the valid flag will be set.
UBXMsg rcvUbxMsg( fd ) {
	struct ubxMsg result;
	result.noMsg = 1;
	result.valid = 0;
	
	int attempts = 0;
	int gotIt = 0;
	int index = 0;
	
	unsigned char header[6];
	
	// first we read the six byte header starting with 0xB5 0x62...
	while( (attempts < 100000) && (gotIt == 0) ) {
		usleep( 50 );
		int x = readUART( fd );
		if( x >= 0 ) {
			header[index] = x;
			switch( index ) {
				case 0: if( x == 0xB5 ) index++; break;
				case 1: if( x == 0x62 ) index++; else index = 0; break;
				default: index++; if( index >= 6 ) gotIt = 1; break;
			}
		}
		attempts++;
	}
	if( !gotIt )
		return result;  // noMsg flag is set by default...
		
	// decode the header...
	result.bodySize = header[4] | (header[5] << 8);
	result.class = header[2];
	result.id = header[3];
	
	// then we read the body, however long it is, plus the two byte checksum...
	gotIt = 0;
	index = 0;
	result.body = calloc( result.bodySize + 2, 1 );
	
	while( (attempts < 100000) && (gotIt == 0) ) {
		usleep( 50 );
		int x = readUART( fd );
		if( x >= 0 ) {
			result.body[index++] = x;
			if( index >= result.bodySize + 2 )
				gotIt = 1;
		}
		attempts++;
	}
	if( !gotIt )
		return result;  // noMsg flag is set by default...
	
	// we got the message, but we're not sure it's valid yet...	
	result.noMsg = 0;
	
	// construct the raw message buffer...
	result.msg = calloc( result.bodySize + 8, 1 );
	memcpy( result.msg, header, 6 );
	memcpy( result.msg + 6, result.body, result.bodySize + 2 );
	
	// now we check to see if the message is valid (checksum matches)...
	// calculate Fletcher checksum for this message...
	unsigned char ck_a = 0;
	unsigned char ck_b = 0;
	int i;
	for( i = 2; i < result.bodySize + 6; i++ ) {
		ck_a += result.msg[i];
		ck_b += ck_a;
	}
	if( (result.msg[result.bodySize + 6] == ck_a) && (result.msg[result.bodySize + 7] == ck_b) ) {
		result.valid = 1;
	}
	return result;
}

// return 0 if error, 1 if succeeded
int sendUbxMsg( int fd, UBXMsg msg ) {
	
	// first we blast the message out...
	//printf("message size: %d\n", msg.size);
	int c = write( fd, msg.msg, msg.size );
	
	free( msg.msg );
	return 1;
} 

// prints the body of the given UBX message in hex, or the raw message if the body is invalid
void printUbxMsg( UBXMsg msg ) {
	int size = msg.body ? msg.bodySize : msg.size;
	unsigned char * buf = msg.body ? msg.body : msg.msg;
	printf( msg.body ? "body:" : "msg:" );
	int i;
	for( i = 0; i < size; i++ ) {
		printf( "%02x:", buf[i] );
	}
	printf( "\n" );
}

// interprets the given port configuration message and prints the result
void printUbxPortConfiguration( UBXMsg msg ) {
	if( msg.noMsg || !msg.valid ) {
		printf( "Missing or invalid port configuration message!\n" );
		return;
	}
	
	// get the baud rate...
	int baud = msg.body[8] | (msg.body[9] << 8) | (msg.body[10] << 16) | (msg.body[11] << 24);
	printf( "%d baud\n", baud );
	
	// get the mode...
	int mode = msg.body[4] | (msg.body[5] << 8) | (msg.body[6] << 16) | (msg.body[7] << 24);
	int bits = 0x03 & (mode >> 6);
	int parity = 0x07 & (mode >> 9);
	int stop = 0x03 & (mode >> 12);
	printf( "%d bits\n", bits + 5 );
	switch( parity ) {
		case 0: printf( "even parity\n" );       break;
		case 1: printf( "odd parity\n" );        break;
		case 4: case 5: printf( "no parity\n" ); break;
		default: printf( "invalid parity\n" );   break;
	}
	switch( stop ) {
		case 0: printf( "1 stop bit\n" );    break;
		case 1: printf( "1.5 stop bits\n" ); break;
		case 2: printf( "2 stop bits\n" );   break;
		case 3: printf( "0.5 stop bits\n" ); break;
	}
}


// toggles the UART's baud rate between 9,600 baud and 115,200 baud
void toggle( int fd, int quiet ) {

	// first we get the current GPS port configuration
	int result = sendUbxMsg( fd, getPortQueryMsg() );
	if( !result ) {
		printf( "Failed to send port query message!\n" );
		exit( 1 );
	}
	UBXMsg cc = rcvUbxMsg( fd );
	if( cc.noMsg || !cc.valid ) {
		printf( "Port query response missing or invalid!\n" );
		exit( 1 );
	}
	
	// now we construct our new port configuration message...
	int curBaud = cc.body[8] | (cc.body[9] << 8) | (cc.body[10] << 16) | (cc.body[11] << 24);
	int newBaud = (curBaud == 9600) ? 115200: 9600;
	cc.body[8] = newBaud;
	cc.body[9] = newBaud >> 8;
	cc.body[10] = newBaud >> 16;
	cc.body[11] = newBaud >> 24;
	UBXMsg setCfg = createUbxMsg( 0x06, 0x00, cc.body, 20 );
	
	// wait until we've had no rx data for at least three characters
	// we're hoping to hit a pause between the GPS sending bursts of characters
	int wt = (curBaud == 9600) ? 2813 : 234;
	int ct = 0;
	while( ct < wt ) {
		usleep( 10 );
		int c = readUART( fd );
		ct = (( c >= 0 ) ? 0 : ct + 10);
	}
	
	// send the configuration message...
	result = sendUbxMsg( fd, setCfg );
	if( !result ) {
		printf( "Failed to send port configuration message!\n" );
		return;
	}
	
	tcdrain( fd ); // wait for the preceding message to finish sending...
	
	// we ignore the expected ACK, because we don't know what baud rate it's going 
	// to come back in
	if( !quiet ) printf( "Port configuration changed to %d baud\n", newBaud );
}


int main( int argc, char *argv[] ) {

//// begin ARGP stuff

  /* Default values. */
  arguments.baudCheck = 0;
  arguments.readPortCfg = 0;
  arguments.echo = 0;
  arguments.quiet = 0;
  arguments.toggle = 0;
  arguments.high = 0;
  arguments.device = 0;

  /* Parse our arguments; every option seen by parse_opt will
     be reflected in arguments. */
  argp_parse (&argp, argc, argv, 0, 0, &arguments);

//// end ARGP stuff

	if( arguments.device == 0 ) { 
		printf( "ERROR: No device given\n" );
		exit(1);
	}

	DEBUG( "INFO: opening device '%s'\n", arguments.device);
	int fd = openUART( arguments.device, arguments.quiet, arguments.high );
	if( fd < 0 ) exit( 1 );

	if( arguments.baudCheck ) {
		DEBUG( "INFO: baudcheck finished '%s'\n", arguments.device);
		close( fd );
		exit( 0 );
	}
	else if( arguments.toggle ) {
		DEBUG( "INFO: toggling baudrate\n");
		toggle( fd, arguments.quiet );
	}
	else if( arguments.readPortCfg ) {
		DEBUG( "INFO: reading config\n");
		int result = sendUbxMsg( fd, getPortQueryMsg() );
		if( result ) {
			UBXMsg answer = rcvUbxMsg( fd );
			printUbxPortConfiguration( answer );
		}
	}
	else if( arguments.echo ) {
		DEBUG( "INFO: serial-port echo (ctrl-c to stop)\n");
		echo( fd );
	}
	exit( 0 );
}

