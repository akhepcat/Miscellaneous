#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <termios.h>
#include <sys/types.h>
#include <sys/stat.h>

/*
	Based on:  https://gist.github.com/SlightlyLoony/d94cce218a9f650e6ad2de6a6ae7550e  
	with additional changes from https://ava.upuaut.net/?p=951

	gcc -o gpsControl gpsControl.c

	sudo ./gpsControl -p -d /dev/ttyAMA0 = Portable Mode
	sudo ./gpsControl -s -d /dev/ttyAMA0 = Stationary Mode
*/

char devName[64];
int option = 0;

struct ubxMsg {
	int size;
	unsigned char* msg;
};

unsigned char stationary[] = {
	0xB5, 0x62,             /* message header */ \
	0x06, 0x24,             /* message class and ID */  \
	0x24, 0x00,             /* message body length */  \
	0xFF, 0xFF,             /* parameters bitmask */ \
	0x02,                   /* dynamic platform model: stationary */ \
	0x03,                   /* position fixing mode: auto 2D/3D */ \
	0x00, 0x00, 0x00, 0x00, /* fixed altitude for 2D fix mode: 0 m */ \
	0x10, 0x27, 0x00, 0x00, /* fixed altitude variance for 2D fix mode: 1 m^2 */ \
	0x05,                   /* minimum elevation for GNSS satellite: 5 degrees */ \
	0x00,                   /* reserved */ \
	0xFA, 0x00,             /* position DOP mask: 0x00FA */ \
	0xFA, 0x00,             /* time DOP mask: 0x00FA */ \
	0x64, 0x00,             /* position accuracy mask: 100 m */ \
	0x2C, 0x01,             /* time accuracy mask: 300 m */ \
	0x00,                   /* static hold threshold: 0 cm/s */ \
	0x3C,                   /* DGNSS timeout: 60 seconds */ \
	0x00,                   /* number of satellites required above C/N0 threshold */ \
	0x00,                   /* C/N0 threshold: 0dBHz */ \
	0x00, 0x00,             /* reserved */ \
	0x00, 0x00,             /* static hold distance threshold: 0 m */ \
	0x00,                   /* UTC standard: auto */ \
	0x00, 0x00, 0x00, 0x00, /* reserved */ \
	0x00,                   /* reserved */ \
	0x4E, 0x60              /* checksum */ \
	};

unsigned char portable[]= {0xB5, 0x62, 0x06, 0x24, 0x24, 0x00, 0xFF, 0xFF, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x10, 0x27, 0x00, 0x00, 0x05, 0x00, 0xFA, 0x00, \
			   0xFA, 0x00, 0x64, 0x00, 0x2C, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x10  }; 

unsigned char save[]	= {0xB5, 0x62, 0x06, 0x09, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x1D, 0xAB};


struct ubxMsg getStationaryMessage() {
    struct ubxMsg result;
    result.msg = stationary;
    result.size = sizeof( stationary );
    return result;
}

struct ubxMsg getPortableMessage() {
    struct ubxMsg result;
    result.msg = portable;
    result.size = sizeof( portable );
    return result;
}

struct ubxMsg getSaveConfigurationMessage() {
	struct ubxMsg result;
	result.msg = save;
	result.size = sizeof( save );
	return result;
}

void usage( void )
{
    printf("Usage: gpsControl <mode> -d <device>\n");
    printf("Modes are:\n");   
    printf("   -s = stationary mode\n");   
    printf("   -p = portable mode\n"); 
    printf("   -d = device \n");    
}

int openUART(char *dName) {
	int fd = -1;
	fd = open(dName, O_RDWR | O_NOCTTY | O_NDELAY);		//Open in non blocking read/write mode

	if (fd == -1)
	{
		printf( "Can't open %s - possibly it's in use by another application\n", dName );
	}

	struct termios options;
	tcgetattr(fd, &options);
	options.c_cflag = B9600 | CS8 | CLOCAL | CREAD;
	options.c_iflag = IGNPAR;
	options.c_oflag = 0;
	options.c_lflag = 0;
	tcflush(fd, TCIFLUSH);
	tcsetattr(fd, TCSANOW, &options);

	return fd;
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


// waits up to five seconds for the given string to be read
// returns 0 for failure, 1 for success
int waitForString( int fd, char* str, int size ) {
	int attempts = 0;
	int gotIt = 0;
	int index = 0;
	while( (attempts < 5000) && (gotIt == 0) ) {
		usleep( 1000 );
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

// return 0 if error, 1 if succeeded
int sendUBXMessage( int fd, struct ubxMsg msg ) {

	// first we wait until our receiver is synchronized, by looking for a message
	// we know should be happening often ("$GNGGA,")
	// we'll wait up to five seconds for this
	if( waitForString( fd, "$GNGGA,", 7 ) == 0 )
		return 0;
	printf( "Synchronized...\n" );
	
	// then we blast the message out...
	//printf("message size: %d\n", msg.size);
	int c = write( fd, msg.msg, msg.size );
	
	// construct our expected acknowledge message and wait for it
	unsigned char expect[] = {0xb5, 0x62, 0x05, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00};
	expect[6] = msg.msg[2];
	expect[7] = msg.msg[3];
	return waitForString( fd, expect, 8 );
} 

int main( int argc, char *argv[] ) {
    int mode=0; // stationary=0, portable=1
    int result;

    memset( devName, 0, sizeof(devName));
    while(( option = getopt( argc, argv, "spd:")) != -1)
    {
        switch( option)
        {
            case 'd':
                printf("Configuring device %s\n", optarg );
                strncpy( devName, optarg, sizeof(devName ));                
                break;

            case 's':
                printf("Set GPS for stationary mode\n");
                mode=0;
                break;

            case 'p': 
                printf("Set GPS for portable mode\n");
                mode=1;
                break;

            default:
               usage();
               return(0);
        }        
    }

    if( devName[0] == 0)
    {
        usage();
        return( 0 );
    }
        
	int fd = openUART(devName);
	if( fd < 0 )
		return 0;

	if (mode == 0) {
		result = sendUBXMessage( fd, getStationaryMessage() );
	} else {
		result = sendUBXMessage( fd, getPortableMessage() );
	}

	if( result == 1 ) {
		printf( "GPS %s mode successfully set...\n", (mode==0?"stationary":"portable") );

		result = sendUBXMessage( fd, getSaveConfigurationMessage() );
		if( result == 1 ) {
			printf( "Configuration successfully saved...\n" );
		}
		else {
			printf( "Failed to save configuration!\n" );
		}
	}
	else {
		printf( "Failed to set %s mode!\n", (mode==0?"stationary":"portable")  );
	}
	close( fd );
}
