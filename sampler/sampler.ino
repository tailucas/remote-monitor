// pins
const byte ledPin = 13;
const byte interruptPin = 2;
const byte dataPin = 3;
// timing constants
const int clock_preamble = 440;
const int clock_duration = 220;
const int clock_idle = 6000;
volatile unsigned long now = 0;
volatile unsigned long last_clock = 0;
volatile unsigned long clock_interval = 0;
// for printing
unsigned long last_print = 0;
unsigned long print_interval = 0;
const long print_frequency = 10000000;
// variables
volatile int bit_pos = 0;
const int word_length = 64;
volatile char data_word[word_length] = {0};
char previous_data_word[word_length+1] = {0};
char output_data_word[word_length+1] = {0};
volatile boolean startup = true;
volatile boolean new_word = true;
boolean first_round = true;
boolean changed = false;

void int_clock() {
  now = micros();
  clock_interval = now - last_clock;
  // update the clock
  last_clock = now;
  // check for the first clock with some tolerance
  if (clock_interval > (clock_preamble-20) && clock_interval < (clock_preamble+20)) {
    bit_pos = 0;
    new_word = false;
    startup = false;
  } else if (bit_pos >= word_length) {
    // the word is complete
    detachInterrupt(0);
    new_word = true;
  }
  // don't read data if we're not in the word
  if (new_word) {
    return;
  }
  // allow the edge to dissipate
  delayMicroseconds(100);
  // read the data (goes low) and shift
  data_word[bit_pos++] = (char) !digitalRead(dataPin);
}

void setup() {
  Serial.begin(9600);
  pinMode(ledPin, OUTPUT);
  pinMode(interruptPin, INPUT);
  pinMode(dataPin, INPUT_PULLUP);
  // older compiler
  //attachInterrupt(digitalPinToInterrupt(interruptPin), int_clock, CHANGE);
  //Board	        int.0	int.1	int.2	int.3	int.4	int.5
  //Uno, Ethernet	2	    3
  attachInterrupt(0, int_clock, CHANGE);
}

void loop() {
  // we're outside of the data word
  if (!startup && new_word) {
    changed = false;
    for (int i=0; i<word_length; i++) {
      output_data_word[i] = data_word[i];
      if (!first_round) {
        if (output_data_word[i] > previous_data_word[i]) {
          //Serial.print(i, DEC);
          //Serial.print(":1");
          Serial.print("1");
          //Serial.print(',');
          changed = true;
        } else if (output_data_word[i] < previous_data_word[i]) {
          //Serial.print(i, DEC);
          //Serial.print(":0");
          Serial.print("0");
          //Serial.print(',');
          changed = true;
        }
      }
      previous_data_word[i] = output_data_word[i];
    }
    first_round = false;
    // we printed, so don't heartbeat
    now = micros();
    if (changed) {
      digitalWrite(ledPin, HIGH);
      last_print = now;
      Serial.println();
    }
    print_interval = now - last_print;
    if (print_interval > print_frequency) {
      for (int i=0; i<word_length; i++) {
        Serial.print(output_data_word[i], DEC);
      }
      Serial.println();
      last_print = now;
    }
    // processing complete, attach the interrupt again
    attachInterrupt(0, int_clock, CHANGE);
  }
  delayMicroseconds(clock_duration);
  digitalWrite(ledPin, LOW);
}
