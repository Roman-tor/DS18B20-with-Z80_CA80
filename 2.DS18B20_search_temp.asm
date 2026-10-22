; ==============================================================================
; BLOK 1: SZUKAJ_ROM (Algorytm WG Maxim AN187 ze sprawdzaniem sumy kontrolnej CRC)
; program wygenerowany przy pomocy AI
; ==============================================================================  
; ZMIENNE W RAM CA80
DEVICE_COUNT:          EQU 0FD60H ; Oficjalny licznik urz¹dzeñ wymagany przez projekt
LICZBA_CZUJNIKOW:      EQU 0FD61H ; Lokalny licznik przebiegu pêtli algorytmu
OSTATNIA_ROZBIEZNOSC:  EQU 0FD62H ; Pozycja ostatniej wykrytej rozbie¿noœci (0-64)
OSTATNIE_ZERO:         EQU 0FD63H ; Pomocnicza pozycja œcie¿ki zerowej
FLAGA_OSTATNIEGO:      EQU 0FD64H ; Znacznik zakoñczenia sprawdzania ca³ego drzewa ID
BIEZACY_WSKAZNIK:      EQU 0FD65H ; 16-bitowy wskaŸnik zapisu kolejnego ID pod NR_ID
TYMCZASOWY_ID:         EQU 0FD67H ; 8-bajtowy bufor na aktualnie budowany numer seryjny
NR_ID:                 EQU 0FD70H ; TU ZAPISUJ ODCZYTANE BAJTY NUMERU SERYJNEGO
SENSOR1_ROM            EQU NR_ID  ; WskaZnik na adres ROM pierwszego czujnika w RAM

LOW:                   EQU 80H     ; STAN NISKI - L
HIGH                   EQU 82H     ; STAN WYSOKI - H
CTRL:                  EQU 0E3H    ; SLOWO KONTROLNE 8255
PORT_DS:               EQU 0E1H    ; TU PODLACZONY DS18B20 port B (PB0)
PRINT:                 EQU 01D4H   ; WYSWIETL KOMUNIKAT WG (HL)

     ORG #C000

SZUKAJ_ROM_START:
    CALL NMI_OFF            ; Zablokowanie przerwañ NMI na czas komunikacji      
    ;  czyszczenie zmiennych w RAM przed startem (likwidacja smieci)
    XOR  A
    LD   (DEVICE_COUNT), A
    LD   (LICZBA_CZUJNIKOW), A
    LD   (OSTATNIA_ROZBIEZNOSC), A
    LD   (OSTATNIE_ZERO), A
    LD   (FLAGA_OSTATNIEGO), A

    ; Ustawienie pocz¹tkowego wskaŸnika zapisu unikalnych ID (0FD70h)
    LD   HL, NR_ID         
    LD   (BIEZACY_WSKAZNIK), HL

PETLA_GLOWNA_SZUKANIA:
    ; Jeœli flaga ostatniego urz¹dzenia jest ustawiona, koñczymy szukanie
    LD   A, (FLAGA_OSTATNIEGO)
    AND  A
    JP   NZ, KONIEC_SZUKANIA

    ; --- Krok 1: Sygna³ Reset i test Presence ---
    CALL OW_RESET
    AND  A                  ; Czy A = 0? (0 oznacza wykrycie obecnoœci czujnika)
    JP   NZ, KONIEC_SZUKANIA ; Jeœli brak odpowiedzi, koñczymy pracê

    ; --- Krok 2: Wys³anie komendy SEARCH ROM (0xF0) ---
    LD   A, 0F0H
    CALL OW_ZAPISZ_BAJT

    ; --- Krok 3: Inicjalizacja zmiennych pêtli bitowej (64 bity) ---
    XOR  A
    LD   (OSTATNIE_ZERO), A 
    LD   C, A               ; C = indeks aktualnego bajtu ID (0 do 7)
    LD   D, 1               ; D = maska bitowa w bajcie (bit 0)

    ; Wyczyszczenie bufora TYMCZASOWY_ID w RAM 
    ; Wyczyszczenie 8 bajtów TYMCZASOWY_ID
    LD   HL, 0FD67H 
    ld B,8
    XOR A
  P1:         
    LD   (HL), A
    INC HL
    DJNZ P1
    
    LD   B, 64              ; Licznik 64 bitów dla PETLA_BITOWA
    LD   E, 1               ; E = Numer bie¿¹cego bitu (1 do 64)

PETLA_BITOWA:
    PUSH BC                 ; Zachowaj licznik bitów (B) i indeks bajtu (C)

    ; Odczyt pierwszego bitu (w³aœciwego)
    CALL OW_ODCZYTAJ_BIT
    LD   H, A               ; H = bit w³aœciwy

    ; Odczyt drugiego bitu (zanegowanego)
    CALL OW_ODCZYTAJ_BIT
    LD   L, A               ; L = bit zanegowany

    ; Analiza stanów bitów wed³ug noty Maxim AN187
    LD   A, H
    AND  A
    JP   NZ, SPRAWDZ_CZY_J00 ; rozbieznosc

    LD   A, L
    AND  A
    JR   NZ, SCIEZKA_ZERO   ; H=0, L=1 -> Wszystkie urz¹dzenia maj¹ tu bit 0

    ; Przypadek H=0, L=0 -> Rozbie¿noœæ (czêœæ czujników ma 0, czêœæ 1)
    LD   A, E               
    LD   B, A               
    LD   A, (OSTATNIA_ROZBIEZNOSC)
    CP   B                  
    JR   C, WYBIERZ_ZERO
    JR   Z, WYBIERZ_JEDEN

    PUSH DE
    LD   HL, TYMCZASOWY_ID
    PUSH BC
    LD   B, 0
    ADD  HL, BC             
    POP  BC
    LD   A, (HL)
    AND  D                  
    POP  DE
    JR   NZ, SCIEZKA_JEDEN
    JR   SCIEZKA_ZERO

WYBIERZ_ZERO:
    LD   A, E
    LD   (OSTATNIE_ZERO), A

SCIEZKA_ZERO:
    XOR  A
    CALL OW_ZAPISZ_BIT
    JR   KONIEC_KROKU_BITU

WYBIERZ_JEDEN:
SCIEZKA_JEDEN:
    LD   A, 1
    CALL OW_ZAPISZ_BIT
    PUSH DE
    LD   HL, TYMCZASOWY_ID
    PUSH BC
    LD   B, 0
    ADD  HL, BC
    POP  BC
    LD   A, (HL)
    OR   D                  
    LD   (HL), A
    POP  DE

KONIEC_KROKU_BITU:
    POP  BC                 ; Przywróæ licznik bitów i indeks bajtu

    ; Aktualizacja maski bitowej D dla nastêpnego bitu w bajcie
    SLA  D                  
    JP   NZ, SKOK_NAST_BIT  
    LD   D, 1               
    INC  C                  

SKOK_NAST_BIT:
    INC  E                  ; Zwiêksz numer rozpatrywanego bitu (1-64)
    DEC  B                  ; Bezpieczna pêtla dekrementacji (zastêpuje DJNZ)
    JR   NZ, PETLA_BITOWA   

    ; --- KROK WERYFIKACJI SUMY KONTROLNEJ CRC-8 ---
    CALL OBLICZ_CRC_ID
    AND  A
    JP   NZ, POMIN_BLEDNY_ROM ; Jeœli wynik != 0, suma CRC jest niepoprawna! Odrzuæ czujnik.

    ; Zapis pomyœlnie zweryfikowanego ID do bazy danych RAM (0FDA0h + ...)
    PUSH BC
    LD   HL, TYMCZASOWY_ID
    LD   A, (BIEZACY_WSKAZNIK)
    LD   E, A
    LD   A, (BIEZACY_WSKAZNIK+1)
    LD   D, A               ; DE = Aktualna pozycja zapisu w RAM
    LD   BC, 8
    LDIR                    ; Skopiuj 8 bajtów kodu ID czujnika
    LD   A, E
    LD   (BIEZACY_WSKAZNIK), A
    LD   A, D
    LD   (BIEZACY_WSKAZNIK+1), A
    POP  BC

    ; Inkrementacja licznika sprawnie zweryfikowanych urz¹dzeñ
    LD   A, (LICZBA_CZUJNIKOW)
    INC  A
    LD   (LICZBA_CZUJNIKOW), A

POMIN_BLEDNY_ROM:
    ; Aktualizacja rozbie¿noœci dla kolejnego przejœcia algorytmu drzewa binarnego
    LD   A, (OSTATNIE_ZERO)
    LD   (OSTATNIA_ROZBIEZNOSC), A
    AND  A
    JP   NZ, PETLA_GLOWNA_SZUKANIA 

    LD   A, 1
    LD   (FLAGA_OSTATNIEGO), A
    JP   PETLA_GLOWNA_SZUKANIA

SPRAWDZ_CZY_J00:
    LD   A, L
    AND  A
    JR   Z, SCIEZKA_JEDEN   

    POP  BC                 ; Czyszczenie stosu w przypadku wykrycia b³êdu magistrali
  
KONIEC_SZUKANIA:
    CALL NMI_ON
    LD   A, (LICZBA_CZUJNIKOW)
    LD   (DEVICE_COUNT), A      ; Zapis ostatecznego wyniku pod 0xFD60
    JP PETLA_WSZYSTKICH_CZUJNIKOW

; ==============================================================================
; PODPROGRAM OBLICZANIA SUMY KONTROLNEJ CRC-8 DALLAS/MAXIM
; Wyjœcie: A = 00h (Sukces), A != 00h (B³¹d sumy kontrolnej)
; ==============================================================================
OBLICZ_CRC_ID:   
    ; SPRAWDZIMY, CZY PIERWSZY ODCZYTANY BAJT = 28H
    LD A, (TYMCZASOWY_ID)
    CP 0  ; PIERWSZY BAJT ID, np. DS18B20
    JR NZ, OBL_CRC2
OBL_CRC1: ; PIERWSZY BAJT = 0 ERROR
    CALL NMI_ON
    LD HL, B_DS
    CALL PRINT
    DEFB 80H
    RST 8 ; CZEKAJ NA WCISNIECIE KLAWISZA
    RST 30H ; MONITOR CA80
OBL_CRC2:
    PUSH BC
    PUSH HL
    LD   HL, TYMCZASOWY_ID
    LD   C, 8               ; Przetwarzamy 8 bajtów pobranego ID
    XOR  A                  ; Zerowanie akumulatora CRC (A = 0)
PETLA_BAJTOW_CRC:
    XOR  (HL)               ; Operacja XOR z bie¿¹cym bajtem
    LD   B, 8               ; Przetwarzamy 8 bitów wewn¹trz bajtu
PETLA_BITOW_CRC:
    SRL  A                  ; Przesuñ rejestr CRC w prawo, bit 0 l¹duje w Carry
    JR   NC, BIT_CRC_ZERO   ; Jeœli Carry = 0, pomiñ operacjê XOR
    XOR  8CH                ; XOR z lustrzanym wielomianem Dallas (0x8C)
BIT_CRC_ZERO:
    DEC  B
    JR   NZ, PETLA_BITOW_CRC
    INC  HL                 ; PrzejdŸ do nastêpnego bajtu
    DEC  C
    JR   NZ, PETLA_BAJTOW_CRC
    POP  HL
    POP  BC
    RET


; --- PROCEDURA RESETU ---
OW_RESET:
    LD   A, LOW             ; Wymuszenie stanu niskiego na PB0
    OUT  (CTRL), A
    LD   A, 66              ; opoz. ok. 264 us
PETLA_OP_RES1:
    DEC  A
    JR   NZ, PETLA_OP_RES1  

    LD   A, HIGH             ; Zwolnienie linii (Stan wysoki przez Pull-up)
    OUT  (CTRL), A
    LD   A, 9   ; opoz. ok. 36 us
PETLA_OP_RES2:
    DEC  A
    JR   NZ, PETLA_OP_RES2

    IN   A, (PORT_DS)          ; Próbkowanie linii DQ
    AND  01H                
    LD   B, A               ; Zachowanie stanu (0 = Presence, 1 = Brak)

    LD   A, 56     ; opoz. ok. 225 us
PETLA_OP_RES3:
    DEC  A
    JR  NZ, PETLA_OP_RES3

    LD   A, B               
    RET

; --- PROCEDURA ZAPISU  BAJTU ---
OW_ZAPISZ_BAJT:
    PUSH BC
    LD   B, 8               
PETLA_ZAPISU_BAJTU:
    RRA                     ; Przesuñ najm³odszy bit bajtu do flagi Carry
    PUSH AF
    JR   C, ZAPISZ_BIT_JEDEN

ZAPISZ_BIT_ZERO:
    LD   A, LOW             
    OUT  (CTRL), A
    LD   A, 8    ; opoz. ok. 32 us               
PETLA_OP_ZAP0:
    DEC  A
    JR  NZ, PETLA_OP_ZAP0
    LD   A, HIGH             
    OUT  (CTRL), A
    JR  KONIEC_ZAPISU_BITU

ZAPISZ_BIT_JEDEN:
    LD   A, LOW             
    OUT  (CTRL), A
    NOP
    NOP
    LD   A, HIGH             
    OUT  (CTRL), A
    LD   A, 8     ; opoz. ok. 32 us            
PETLA_OP_ZAP1:
    DEC  A
    JR  NZ, PETLA_OP_ZAP1

KONIEC_ZAPISU_BITU:
    POP  AF
    DEC  B
    JR   NZ, PETLA_ZAPISU_BAJTU
    POP  BC
    RET

; --- PROCEDURA ODCZYTU POJEDYNCZEGO BITU ---
OW_ODCZYTAJ_BIT:
    LD   A, LOW             ; Wymuszenie stanu niskiego (start szczeliny)
    OUT  (CTRL), A
    NOP
    NOP                     
    LD   A, HIGH             ; Zwolnienie linii
    OUT  (CTRL), A
    NOP
    NOP
    IN   A, (PORT_DS)          ; Próbkowanie portu przed up³ywem 15 us
    AND  01H                
    LD   B, A               
    LD   A, 7    ; opoz. ok. 28 us              
PETLA_OP_ODC:
    DEC  A
    JR   NZ, PETLA_OP_ODC
    LD   A, B               
    RET

; --- PROCEDURA ZAPISU POJEDYNCZEGO BITU ---
OW_ZAPISZ_BIT:
    AND  01H
    JR   NZ, ZAPISZ_POJEDYNCZY_JEDEN
    
    LD   A, LOW
    OUT  (CTRL), A
    LD   A, 8    ; opoz. ok. 32 us
PETLA_BIT_Z0:
    DEC  A
    JR   NZ, PETLA_BIT_Z0
    LD   A, HIGH
    OUT  (CTRL), A
    RET

ZAPISZ_POJEDYNCZY_JEDEN:
    LD   A, LOW
    OUT  (CTRL), A
    NOP
    NOP
    LD   A, HIGH
    OUT  (CTRL), A
    LD   A, 8   ; opoz. ok. 32 us
PETLA_BIT_Z1:
    DEC  A
    JR   NZ, PETLA_BIT_Z1
    RET
    
 ; --- PODPROGRAMY POMOCNICZE ---
OW_WYSLIJ_ADRES_ROM:
    PUSH BC
    LD   C, 8               
PETLA_WYSYLANIA_ROM:
    LD   A, (HL)            
    PUSH HL
    CALL OW_ZAPISZ_BAJT     
    POP  HL
    INC  HL                 
    DEC  C
    JR   NZ, PETLA_WYSYLANIA_ROM
    POP  BC
    RET

OW_ODCZYTAJ_BAJT:
    PUSH BC
    LD   C, 8               
    XOR  A                  
PETLA_ODCZYTU_BAJTU:
    PUSH AF                 
    CALL OW_ODCZYTAJ_BIT    
    LD   B, A               
    POP  AF                 
    RR   B                  
    RRA                     
    DEC  C
    JR   NZ, PETLA_ODCZYTU_BAJTU
    POP  BC
    RET
      
NMI_ON: ; ENABLE NMI wlacz przerwania NMI /obsluga NMI trwa min. ok. 130 uS
    LD A, 7; ; stan H  ; opoznienia NIE MOGA wykorzystywac HALT i innych procedur zwiazanych z NMI!!!
    OUT (0F9h), A  ; ustaw bit PC4 port 8255 /systemowego/ na "1"
    LD A, 0FAh
    OUT (0F9h), A
    RET

NMI_OFF: ; wylacz przerwania NMI - DISABLE NMI
    LD A, 3 ; stan L, ustaw bit PC4 na "0"
    OUT (0F9h), A
    RET
     ; brak czujnika 
b_ds:  defb 54h, 5Ch, 8, 5Eh, 0EDh,79H,50H, 50H, 255  ; "no dS" ma CA80 
; ==============================================================================
; BLOK 2 I BLOK 3: SEKWENCYJNY ODCZYT I WYŒWIETLANIE (Wersja bez Skip ROM)
; ZNAK_TEMP '-' na CYF4, numer czujnika na CYF7 lub CYF6 i CYF7 gdy ilosc >= 10 patrz opis <WYSWIETL_NUMER_CZUJNIKA>
; ==============================================================================

; ---  ZMIENNe W RAM CA80 ---
LSB_TEMP:              EQU 0FEB0H ; Bezpieczne miejsce na LSB z odczytu
MSB_TEMP:              EQU LSB_TEMP+1 ;0FDB1H ; Bezpieczne miejsce na MSB z odczytu
NR_CZUJNIKA:           EQU MSB_TEMP+1 ;0FDB2H ; Numer porz¹dkowy czujnika (1, 2, 3...)
WSKAZNIK_ROM_PETLA:    EQU NR_CZUJNIKA+1 ;0FDB3H ; 2 bajty - adres aktualnego ID w bazie RAM
ZNAK_TEMP:             EQU WSKAZNIK_ROM_PETLA+2 ;0FDB5H ; 0 = dodatnia, 1 = ujemna
CYF0:         EQU 0FFF7H
CYF1:         EQU 0FFF8H         ;cyfra do wyswietlania na CA80
CYF2:         EQU 0FFF9H
CYF3:         EQU 0FFFAH
CYF4:         EQU 0FFFBH
CYF5:         EQU 0FFFCH
CYF6:         EQU 0FFFDH
CYF7:         EQU 0FFFEH

PETLA_WSZYSTKICH_CZUJNIKOW:
    RST 18H
    DEFB 26H ; WYSWIETL ILOSC ZNALEZIONYCH CZYJNKOW
    CALL  OPOZN_2_SEK

 PWC:    ; Sprawdzenie czy w ogóle wykryto jakiekolwiek urz¹dzenia
    LD   A, (DEVICE_COUNT)        ; Odczytaj stan DEVICE_COUNT z Bloku 1
    AND  A
    RET  Z                  ; Jeœli 0, wyjdŸ (brak urz¹dzeñ)

    ; Inicjalizacja wskaŸników dla nowego pe³nego cyklu pomiaru

    LD   HL, NR_ID         ; Zaczynamy od pierwszego ID w bazie danych RAM
    LD   (WSKAZNIK_ROM_PETLA), HL
    LD   A, 1
    LD   (NR_CZUJNIKA), A ; Pierwszy czujnik ma numer 1

PETLA_SEKWENCYJNA:
    ; --- KROK A: Uruchomienie konwersji (Convert T) dla konkretnego czujnika ---
    CALL NMI_OFF            ; Blokada NMI na czas transmisji 1-Wire
    CALL OW_RESET
    JP   NZ, OBL_CRC1

    LD   A, 55H             ; MATCH ROM -  BEDZIEMY ADRESOWALI JEDEN CZUJNIK
    CALL OW_ZAPISZ_BAJT

    ; Pobierz adres unikalnego ID aktualnego czujnika
    LD   A, (WSKAZNIK_ROM_PETLA)
    LD   L, A
    LD   A, (WSKAZNIK_ROM_PETLA+1)
    LD   H, A               ; HL = Adres ID w RAM
    CALL OW_WYSLIJ_ADRES_ROM

    LD   A, 44H             ; CONVERT T (Zlecenie pomiaru tylko temu jednemu uk³adowi)
    CALL OW_ZAPISZ_BAJT
    CALL NMI_ON             ; W³¹czenie NMI na czas konwersji temperatury

    ; Odczekanie 750 ms na zakoñczenie pomiaru przez ten konkretny uk³ad
    LD   B, 75       ; 750 ms dotyczy odzielczosci 12-bit, jesli mniejsza, mozna zmniejszyc
PETLA_KONV_G:
    LD   DE, 1333
PETLA_KONV_W:
    DEC  DE
    LD A, D
     OR E
     JR NZ, PETLA_KONV_W
    DEC  B
    JR NZ, PETLA_KONV_G

    ; --- KROK B: Odczyt Scratchpadu tego samego czujnika ---
    CALL NMI_OFF            ; Blokada NMI przed odczytem
    CALL OW_RESET
    JP   NZ, OBL_CRC1

    LD   A, 55H             ; MATCH ROM
    CALL OW_ZAPISZ_BAJT

    ; Ponowne przes³anie tego samego adresu ID
    LD   A, (WSKAZNIK_ROM_PETLA)
    LD   L, A
    LD   A, (WSKAZNIK_ROM_PETLA+1)
    LD   H, A               
    CALL OW_WYSLIJ_ADRES_ROM

    LD   A, 0BEH            ; READ SCRATCHPAD
    CALL OW_ZAPISZ_BAJT

    ; Bezpoœredni odczyt danych pod bezpieczne adresy potokowe
    CALL OW_ODCZYTAJ_BAJT
    LD   (LSB_TEMP), A      ; Wpisz LSB pod 0xFDB0
    CALL OW_ODCZYTAJ_BAJT
    LD   (MSB_TEMP), A      ; Wpisz MSB pod 0xFDB1
    CALL NMI_ON             ; Przywrócenie NMI dla odœwie¿ania LED
    
    CALL REJESTRUJ_MIN_MAX ; zapisz max i min teperatury i czujnik

    ; --- KROK C: Przeliczenie i wyœwietlenie (Wywo³anie Bloku 3) ---
    CALL KONWERSJA_TEMP    ; Wylicza temperaturê i wyswietla na CA80

  ; --- KROK D: ZW£OKA OK. 10 SEKUND Z MONITOROWANIEM KLAWIATURY ---
    ; Wykonujemy 1000 powtórzeñ po 10 ms, wywo³uj¹c wewn¹trz procedurê klawiatury.
    LD   BC, 1000           
PETLA_10S_DLA_KLAWIATURY:
    PUSH BC                 ; Schowaj licznik BC na stosie
    
    ; Precyzyjna pêtla opóŸniaj¹ca 10 ms dla  4 MHz
    LD   DE, 1333           
PETLA_10MS:
    DEC  DE 
    LD   A, D 
    OR   E 
    JP   NZ, PETLA_10MS

    ; Wywo³anie procedury badania klawiszy D (MIN temp)  i F (MAX temp)
    CALL SPRAWDZ_KLAWIATURE 

    POP  BC                 ; Przywróæ licznik BC ze stosu
    DEC  BC
    LD   A, B
    OR   C
    JP   NZ, PETLA_10S_DLA_KLAWIATURY ; Powtarzaj, a¿ minie pe³ne 10 sekund

    ; --- KROK E: Sprawdzenie warunku koñca pêtli czujników ---
    LD   A, (DEVICE_COUNT)  ; Odczytaj stan DEVICE_COUNT
    LD   B, A               ; B = Ca³kowita liczba znalezionych urz¹dzeñ
    LD   A, (NR_CZUJNIKA)   ; aktualnie mierzony wyswietlany
    CP   B                  ; Czy wyœwietlono ju¿ pomiar z ostatniego czujnika?
    JP   Z, PWC ; Jeœli tak, zamknij cykl i zacznij od nowa

    ; Przejœcie do kolejnego urz¹dzenia na liœcie
    INC  A
    LD   (NR_CZUJNIKA), A ; Zwiêksz numer czujnika na pozycji CYF7

    ; Przesuniêcie wskaŸnika bazy danych o 8 bajtów (skok do kolejnego ID w RAM)
    LD   A, (WSKAZNIK_ROM_PETLA)
    ADD  A, 8
    LD   (WSKAZNIK_ROM_PETLA), A
    LD   A, (WSKAZNIK_ROM_PETLA+1)
    ADC  A, 0
    LD   (WSKAZNIK_ROM_PETLA+1), A

    JP   PETLA_SEKWENCYJNA  ; Skok do obs³ugi kolejnego czujnika

; BLOK 3:  KONWERSJA TEMPERATURY, dokladnosc 1/10 st. C 
;         i WYSWIETLENIE TEMPERATURY
KONWERSJA_TEMP:
    RST 10H ; D7 CZYSC WYSW.
    DEFB 25H
    XOR A
    LD   (ZNAK_TEMP), A
    LD A, 63H  ;  znak stopnia, maly kwadrat
    LD (CYF0), A
         ; zaladuj odczytana temperature z czujnika
    LD HL, (LSB_TEMP)
       ; SprawdŸ ZNAK_TEMP liczby (najstarszy bit MSB)
    BIT     7, H
    JR      Z, DODATNIA     ; Jeœli bit 7 == 0, temperatura jest dodatnia

        ;  Obs³uga temperatury ujemnej (zamiana na wartosc bezwzglêdna -  U2)
    LD      A, 1
    LD      (ZNAK_TEMP), A
    LD      A, H
    CPL
    LD      H, A
    LD      A, L
    CPL
    LD      L, A
    INC     HL   

 DODATNIA:
    LD A, L ; jednosci i dziesietne
    LD E, L
    AND 0F0H
    LD L, A
    LD A, E ;  interseuja nas tylko DZIESIETNE 
    AND 0Fh
    PUSH AF ; zapamietanie dziesietnych       
    RL H
    RL H
    RL H
    RL H

    RR L
    RR L
    RR L
    RR L
    LD A, L
    OR H  ; HL = SETKI, DZIESIATKI I JEDNOSCI JAKO HEX
       
Hex_To_BCD:
        ; A = liczba Hex (np. 0x72) do zamiany na BCD
    LD      H, 0            ; Wyzeruj H (tutaj zbierzemy setki)

    ; --- 1. Wyznaczenie "setek" poprzez odejmowanie 100 (0x64 w Hex) ---
Petla_Setek:
    CP      100           ; Czy A >= 100 (0x64)?
    JR      C, Koniec_Setek
    SUB     100            ; Odejmij 100 dziesiêtnie (szesnastkowo 0x64)
    INC     H               ; Zwiêksz licznik setek
    JR      Petla_Setek
Koniec_Setek:

    ; Przesuñ setki na starszy pó³bajt rejestru H
    PUSH    AF              ; Zachowaj resztê (< 100)
    LD      A, H
    SLA     A
    SLA     A
    SLA     A
    SLA     A
    LD      H, A            ; H ma setki na starszych bitach
    POP     AF              ; Przywróæ resztê do A

    ; --- 2. Wyznaczenie Dziesi¹tek poprzez odejmowanie 10 (0x0A w Hex) ---
    LD      B, 0            ; B = licznik dziesi¹tek
Petla_Dziesiatek:
    CP      10           ; Czy A >= 10 (0x0A)?
    JR      C, Koniec_Dziesiatek
    SUB     10            ; Odejmij 10 dziesiêtnie (0x0A)
    INC     B               ; Zwiêksz licznik dziesi¹tek
    JR      Petla_Dziesiatek
Koniec_Dziesiatek:

    ; W A zosta³a reszta, czyli czyste Jednoœci (0-9)
    ; Po³¹cz setki (w H) z dziesi¹tkami (w B)
    LD      C, A            ; C = zachowaj jednoœci na chwilê
    LD      A, H           
    OR      B               ; Po³¹cz setki i dziesi¹tki w jednym bajcie
    LD      H, A            ; H = [Setki | Dziesi¹tki] -gotowe!

    ; --- 3. Umieszczenie Jednoœci na starszym pó³bajcie rejestru L ---
    LD      A, C            ; Pobierz jednoœci (0-9)
    SLA     A
    SLA     A
    SLA     A
    SLA     A              ; Przesuñ na starszy pó³bajt
   
    LD      L, A            ; L = [Jednoœci 0 - 9]

; = = = U L A M E K  1/10 st. C
; Konwersja u³amka 1/16 (m³odszy pó³bajt L) na cyfrê dziesiêtn¹ 0-9
; Wejœcie: A = bajt zawieraj¹cy u³amek na m³odszym pó³bajcie (np. 0x0A)
; Wyjœcie: L = starszy polbajt - jednosci, mlodszy - dzisietne 1/10 cyfra dziesiêtna (0-9)

Przelicz_Ulamek:
    POP     AF ; odtworz dziesietne

     ; Krok 1: Mno¿enie przez 10 ( A = A * 10 ) 
    LD      B, A            ; B = X
    SLA     A               ; A = 2 * X
    SLA     A               ; A = 4 * X
    SLA     A               ; A = 8 * X
    ADD     A, B            ; A = 9 * X
    ADD     A, B            ; A = 10 * X
   
    ; Krok 2: Dzielenie przez 16 (przesuniêcie w prawo o 4 bity)
    SRL     A
    SRL     A
    SRL     A
    SRL     A               ; W A zostaje gotowa cyfra dziesiêtna (0-9)
   
    OR      L               ; Po³¹cz u³amek (m³odszy pó³bajt) ze starym L (starszy pó³bajt)
    LD      L, A            ; Teraz L ma gotowy format: [Jednoœci | Czesc dziesietna]
                ;  HL = SETKI, DZISIATKI, JEDNOSCI DZIESIETNE,NP,102,3 [Sst. C]
   
        ; 4. WYSWIETL TEMPERATURE 
        RST  20H  ; E7 WYSW. ZAWARTOSC HL
        DEFB 41H        
        BIT 4, H
        JR NZ, ZAP2
        LD A, H
        CP 0
        JR Z, ZAP1         
      
        RST 10H ; D7 CZYSC
        DEFB 14H ; CYF4
        JR ZAP2
ZAP1:   RST 10H
        DEFB 23H
ZAP2:     LD   HL, CYF2 
        set 7, (HL)

        LD A, (ZNAK_TEMP)
        CP 0
        JR Z, WYSWIETL_NUMER_CZUJNIKA
        LD A, 40H ; " - :
        LD (CYF4), A

WYSWIETL_NUMER_CZUJNIKA: ; jesli czujnikow >= 10, zmien  defb na 26h
    ; CYF7 -> Wyœwietlenie numeru bie¿¹cego czujnika
        LD   A, (NR_CZUJNIKA)
        RST  18H
        DEFB 17H ; jesli czujnikow >= 10 to DEFB 26h !!
        RET   ; Powrót z programu KONWERSJA_TEMP 
    
; =====================================

SYS_MIN:               EQU 0FFEEH   ; SYSTEMOWY CZAS / DATA CA80
SYS_GODZ:              EQU 0FFEFH 
SYS_DZIEN:             EQU 0FFF1H 
SYS_MIES:              EQU 0FFF2H 

MIN_TEMP_BRAM:         EQU 0FD50H ; 2 bajty - najni¿sza temp. (LSB/MSB)
MAX_TEMP_BRAM:         EQU 0FD52H ; 2 bajty - najwy¿sza temp. (LSB/MSB)

REJESTR_MIN_RAM:       EQU 0FEF0H ; Start stempla MIN (zajmuje 7 bajtów: FEF0-FEF6)
REJESTR_MAX_RAM:       EQU 0FEF7H ; Start stempla MAX (zajmuje 7 bajtów: FEF7-FEFD)

; ==============================================================================
; PODPROGRAM: REJESTRUJ_MIN_MAX (Wersja : Czas + Nr + Temperatura)
; ==============================================================================
REJESTRUJ_MIN_MAX:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    EXX
    ; --- SPRAWDZENIE FLAGI INICJALIZACJI GLOBALNEJ (0xFEFE) ---
    LD   A, (REJESTR_MAX_RAM+7)
    CP   55H                ; Czy system zosta³ ju¿ zainicjalizowany baz¹ startow¹?
    JP   Z, POROWNAJ_Z_MINIMUM ; Jeœli tak (wartoœæ 55h), przejdŸ bezpoœrednio do porównañ

    ; --- INICJALIZACJA STARTOWA (WYKONA SIÊ TYLKO RAZ PO W£¥CZENIU CA80) ---
    ; Wymuszamy wpisanie bie¿¹cej temperatury z RAM jako pierwszego rekordu MIN i MAX
    LD   A, (LSB_TEMP)      ; Pobierz LSB z 0xFDB0
    LD   (REJESTR_MIN_RAM+5), A        ; Zapisz jako LSB dla MIN
    LD   (REJESTR_MAX_RAM+5), A        ; Zapisz jako LSB dla MAX

    LD   A, (MSB_TEMP)      ; Pobierz MSB z 0xFDB1
    LD   (REJESTR_MIN_RAM+6), A        ; Zapisz jako MSB dla MIN
    LD   (REJESTR_MAX_RAM+6), A        ; Zapisz jako MSB dla MAX

    ; Zapisz datê, czas i numer czujnika dla obu stempli startowych
    CALL ZAPISZ_STEMPEL_MIN_DIRECT
    CALL ZAPISZ_STEMPEL_MAX_DIRECT

    ; Ustaw flagê inicjalizacji na 55h, aby trwale zablokowaæ tê sekcjê
    LD   A, 55H
    LD   (REJESTR_MAX_RAM+7), A
    JP   KONIEC_REJESTRACJI

; ==============================================================================
; 1. BLOK SPRAWDZANIA GLOBALNEGO MINIMUM
; ==============================================================================
POROWNAJ_Z_MINIMUM:
    ; Wczytanie dotychczasowego rekordowego MINIMUM do HL prosto z 0xFEF5/6
    LD   A, (REJESTR_MIN_RAM+5)
    LD   L, A
    LD   A, (REJESTR_MAX_RAM+6)
    LD   H, A               ; HL = Dotychczasowe Minimum

    ; £adujemy temperaturê bie¿¹cego czujnika do DE
    LD   A, (LSB_TEMP)
    LD   E, A
    LD   A, (MSB_TEMP)
    LD   D, A               ; DE = Bie¿¹ca temperatura

    ; Test MINIMUM: (Bie¿¹ca - Stare_MIN) -> (DE - HL)
    PUSH DE
    OR   A                  ; Czyszczenie Carry
    EX   DE, HL             ; HL = Bie¿¹ca, DE = Stare_MIN
    SBC  HL, DE             ; HL = Bie¿¹ca - Stare_MIN
    POP  DE

    ; Jeœli wynik dodatni lub zero (P), bie¿¹ca temperatura nie jest ni¿sza.
    ; Pomijamy zapis minimum i przechodzimy do testu maksimum.
    JP   P, TEST_MAKSIMUM

    ; --- ZAPIS NOWEGO REKORDU MINIMUM (WYKONA SIÊ GDY DE < MIN) ---
    LD   A, E
    LD   (REJESTR_MIN_RAM+5), A        ; Zapisz nowe LSB bezpoœrednio pod 0xFEF5
    LD   A, D
    LD   (REJESTR_MIN_RAM+6), A        ; Zapisz nowe MSB bezpoœrednio pod 0xFEF6

    ; Zaktualizuj stempel czasu i numer czujnika dla Minimum
    CALL ZAPISZ_STEMPEL_MIN_DIRECT
    JP   KONIEC_REJESTRACJI ; Jeœli pobi³ rekord zimna, nie sprawdzamy ciep³a w tym kroku

; ==============================================================================
; 2. BLOK SPRAWDZANIA GLOBALNEGO MAKSIMUM
; ==============================================================================
TEST_MAKSIMUM:
    ; Wczytanie dotychczasowego rekordowego MAKSIMUM do HL prosto z 0xFEFC/D
    LD   A, (REJESTR_MAX_RAM+5)
    LD   L, A
    LD   A, (REJESTR_MAX_RAM+6)
    LD   H, A               ; HL = Dotychczasowe Maksimum

    ; Œwie¿e za³adowanie temperatury bie¿¹cego czujnika do DE
    LD   A, (LSB_TEMP)
    LD   E, A
    LD   A, (MSB_TEMP)
    LD   D, A               ; DE = Bie¿¹ca temperatura

    ; Test MAKSIMUM: (Stare_MAX - Bie¿¹ca) -> (HL - DE)
    PUSH DE
    OR   A                  ; Czyszczenie Carry
    SBC  HL, DE             ; HL = Stare_MAX - Bie¿¹ca
    POP  DE

    ; Jeœli wynik dodatni lub zero (P), bie¿¹ca temperatura nie jest wy¿sza -> koniec.
    JP   P, KONIEC_REJESTRACJI

    ; --- ZAPIS NOWEGO REKORDU MAKSIMUM (WYKONA SIÊ GDY DE > MAX) ---
    LD   A, E
    LD   (REJESTR_MAX_RAM+5), A        ; Zapisz nowe LSB bezpoœrednio pod 0xFEFC
    LD   A, D
    LD   (REJESTR_MAX_RAM+6), A        ; Zapisz nowe MSB bezpoœrednio pod 0xFEFD

    ; Zaktualizuj stempel czasu i numer czujnika dla Maksimum
    CALL ZAPISZ_STEMPEL_MAX_DIRECT

KONIEC_REJESTRACJI:
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET

; --- PODPROGRAM POMOCNICZY: ZAPIS STEMPLA (BEZ ZMIAN) ---
ZAPISZ_STEMPEL_CZASU:
    ; Sprawdzamy na bazie m³odszego bajtu rejestru L, czy obs³ugujemy MIN czy MAX
    LD   A, L
    CP   0F0H               ; Jeœli L = F0h, stemplujemy rejestr MIN
    JP   NZ, STEMPLUJ_MAX

; --- BEZWZGLÊDNY ZAPIS REJESTRU MINIMUM (0xFEF0 - 0xFEF6) ---
    LD   A, (SYS_DZIEN)
    LD   (REJESTR_MIN_RAM), A        ; 1. Dzieñ
    LD   A, (SYS_MIES)
    LD   (REJESTR_MIN_RAM+1), A        ; 2. Miesi¹c
    LD   A, (SYS_GODZ)
    LD   (REJESTR_MIN_RAM+2), A        ; 3. Godzina
    LD   A, (SYS_MIN)
    LD   (REJESTR_MIN_RAM+3), A        ; 4. Minuta
    
    LD   A, (NR_CZUJNIKA)
    LD   (REJESTR_MIN_RAM+4), A        ; 5. Numer czujnika (Pewny odczyt z RAM 0xFDB2)
    
    LD   A, (LSB_TEMP)
    LD   (REJESTR_MIN_RAM+5), A        ; 6. LSB temperatury MIN (Pewny odczyt z RAM 0xFDB0)
    
    LD   A, (MSB_TEMP)
    LD   (REJESTR_MIN_RAM+6), A        ; 7. MSB temperatury MIN (Pewny odczyt z RAM 0xFDB1)
    RET

; --- BEZWZGLÊDNY ZAPIS REJESTRU MAKSIMUM (0xFEF7 - 0xFEFD) ---
STEMPLUJ_MAX:
    LD   A, (SYS_DZIEN)
    LD   (REJESTR_MAX_RAM), A        ; 1. Dzieñ
    LD   A, (SYS_MIES)
    LD   (REJESTR_MAX_RAM+1), A        ; 2. Miesi¹c
    LD   A, (SYS_GODZ)
    LD   (REJESTR_MAX_RAM+2), A        ; 3. Godzina
    LD   A, (SYS_MIN)
    LD   (REJESTR_MAX_RAM+3), A        ; 4. Minuta
    
    LD   A, (NR_CZUJNIKA)
    LD   (REJESTR_MAX_RAM+4), A        ; 5. Numer czujnika (Pewny odczyt z RAM 0xFDB2)
    
    LD   A, (LSB_TEMP)
    LD   (REJESTR_MAX_RAM+5), A        ; 6. LSB temperatury MAX (Pewny odczyt z RAM 0xFDB0)
    
    LD   A, (MSB_TEMP)
    LD   (REJESTR_MAX_RAM+6), A        ; 7. MSB temperatury MAX (Pewny odczyt z RAM 0xFDB1)
    RET

; ==============================================================================
; KOMPLETNA PROCEDURA: SPRAWDZ_KLAWIATURE (WERSJA Z PODWÓJNYM EKRANEM)
; Najpierw pokazuje temperaturê przez 4s, potem czas przez kolejne 4s.
; ==============================================================================
CSTS:           EQU 0FFC3H 

; Komórki bufora bezpieczeñstwa w RAM
KOPIA_LSB:      EQU 0FEB6H 
KOPIA_MSB:      EQU 0FEB7H 
KOPIA_NUMERU:   EQU 0FEB8H 

SPRAWDZ_KLAWIATURE:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    ; Wywo³anie systemowej procedury skanowania klawiatury CA80
    CALL CSTS        ; Wynik wraca bezpoœrednio w rejestrze A
    
    CP   0DH   ; klawisz " D "
    JP   Z, POKAZ_REKORD_MIN

    CP   0FH   ; klawisz " F "
    JP   Z, POKAZ_REKORD_MAX

    JP   KONIEC_KLAWIATURY

POKAZ_REKORD_MIN:
    ; --- KROK 1: KOPIA BEZPIECZEÑSTWA ---
    LD   A, (LSB_TEMP)
    LD   (KOPIA_LSB), A
    LD   A, (MSB_TEMP)
    LD   (KOPIA_MSB), A
    LD   A, (NR_CZUJNIKA)
    LD   (KOPIA_NUMERU), A

    ; --- KROK 2: WYŒWIETLENIE SAMEJ TEMPERATURY MIN (Przez 4 sekundy) ---
    LD   A, (REJESTR_MIN_RAM+5)        ; £adujemy LSB temperatury MIN
    LD   (LSB_TEMP), A
    LD   A, (REJESTR_MIN_RAM+6)        ; £adujemy MSB temperatury MIN
    LD   (MSB_TEMP), A
    LD   A, (REJESTR_MIN_RAM+4)        ; £adujemy numer czujnika MIN
    LD   (NR_CZUJNIKA), A

    CALL KONWERSJA_TEMP    ; Wywo³anie Bloku 3 (Ekran poka¿e temperaturê)
    CALL OPOZN_2_SEK    ; Odczekanie pierwszych 4 sekund

    ; --- KROK 3: WYŒWIETLENIE DATY I CZASU MIN (Przez kolejne 4 sekundy) ---
    LD   HL, REJESTR_MIN_RAM ;0FEF0H         ; HL wskazuje na pocz¹tek stempla MIN (Dzieñ)
    CALL PRZYGOTUJ_I_WYSWIETL_DATETIME
    CALL OPOZN_2_SEK    ; Odczekanie kolejnych 4 sekund
    JP   PRZYWROC_STAN_NORMALNY

POKAZ_REKORD_MAX:
    ; --- KROK 1: KOPIA BEZPIECZEÑSTWA ---
    LD   A, (LSB_TEMP)
    LD   (KOPIA_LSB), A
    LD   A, (MSB_TEMP)
    LD   (KOPIA_MSB), A
    LD   A, (NR_CZUJNIKA)
    LD   (KOPIA_NUMERU), A

    ; --- KROK 2: WYŒWIETLENIE SAMEJ TEMPERATURY MAX (Przez 4 sekundy) ---
    LD   A, (REJESTR_MAX_RAM+5)        ; £adujemy LSB temperatury MAX
    LD   (LSB_TEMP), A
    LD   A, (REJESTR_MAX_RAM+6)        ; £adujemy MSB temperatury MAX
    LD   (MSB_TEMP), A
    LD   A, (REJESTR_MAX_RAM+4)        ; £adujemy numer czujnika MAX
    LD   (NR_CZUJNIKA), A

    CALL KONWERSJA_TEMP    ; Wywo³anie Bloku 3 (Ekran poka¿e temperaturê)
    CALL OPOZN_2_SEK    ; Odczekanie pierwszych 4 sekund

    ; --- KROK 3: WYŒWIETLENIE DATY I CZASU MAX (Przez kolejne 4 sekundy) ---
    LD   HL, REJESTR_MAX_RAM   ;0FEF7H         ; HL wskazuje na pocz¹tek stempla MAX (Dzieñ)
    CALL PRZYGOTUJ_I_WYSWIETL_DATETIME
    CALL OPOZN_2_SEK    ; Odczekanie kolejnych 4 sekund

PRZYWROC_STAN_NORMALNY:
    ; Przywrócenie pierwotnego stanu z kopii bezpieczeñstwa w RAM
    LD   A, (KOPIA_LSB)
    LD   (LSB_TEMP), A
    LD   A, (KOPIA_MSB)
    LD   (MSB_TEMP), A
    LD   A, (KOPIA_NUMERU)
    LD   (NR_CZUJNIKA), A

    CALL KONWERSJA_TEMP    ; Wróæ na ekranie do bie¿¹cej temperatury

KONIEC_KLAWIATURY:
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET

; ==============================================================================
; PODPROGRAM POMOCNICZY: PRZYGOTUJ_I_WYSWIETL_DATETIME
; Mapuje Datê i Czas w uk³adzie: DDMM GG.M bezpoœrednio do rejestrów LED CA80
; ==============================================================================
PRZYGOTUJ_I_WYSWIETL_DATETIME:
    PUSH HL
    PUSH DE
    PUSH BC

    ; --- 1. DZIEN (Komórka [HL]) -> CYF7 (0xFFFE) i CYF6 (0xFFFD) ---
    LD   A, (HL)            ; Pobierz bajt dnia ze stempla:0xFEF0
    RST 18H
    DEFB 26H
    INC  HL                 ; HL wskazuje na Miesi¹c 0xFEF1

    ; --- 2. MIESIAC (Komórka [HL]) -> CYF5 (0xFFFC) i CYF4 (0xFFFB) ---
    LD   A, (HL)            ; Pobierz bajt miesi¹ca 
    RST 18H
    DEFB 24H
    INC  HL                 ; HL wskazuje na Godzinê 0xFEF2

    ; --- 3. CYF3 (0xFFFA) -> WYGASZENIE (Separator wizualny w œrodku ekranu) ---
    XOR  A
    LD   (CYF3), A        ; CYF3 = 00h (Pusty, ciemny segment)

    ; --- 4. MINUTA (Komórka [HL]) -> CYF0 (0xFFF7) ---
    INC HL   ; 0xFEF3
    LD   A, (HL)            ; Pobierz bajt minut
   ; CALL ROZBIJ_NA_DWIE_CYFRY
    RRA
    RRA
    RRA
    RRA
    RST 18H ; WYSW. REJ. A
    DEFB 10H

    ; --- 5. GODZINA (Komórka [HL]) -> CYF2 (0xFFF9) i CYF1 (0xFFF8) ---
    DEC HL  ; 0xFEF1
    LD   A, (HL)            ; Pobierz bajt godziny
    RST 18H
    DEFB 21H
    LD A, (CYF1)
    OR 80H  
                ; Zapal bit 7 (kropka dziesiêtna) jako separator czasu
    LD   (CYF1), A        ; CYF1 = Jednoœci godziny z kropk¹
           
    POP  BC
    POP  DE
    POP  HL
    RET

; ==============================================================================
; PODPROGRAM POMOCNICZY: OPOZN_4_SEK (Z zachowaniem odœwie¿ania NMI)
; ==============================================================================
OPOZN_2_SEK:
    PUSH AF
    PUSH BC
    PUSH DE
    LD   C, 2               ; 2 * 1 sekunda = 4s
PETLA_2S_Z:
    LD   B, 100             ; 100 * 10 ms = 1 sekunda
PETLA_2S_INTERN:
    LD   DE, 1333           
PETLA_2S_DELAY:
    DEC  DE
    LD   A, D
    OR   E
    JP   NZ, PETLA_2S_DELAY
    DEC  B
    JP   NZ, PETLA_2S_INTERN
    DEC  C
    JP   NZ, PETLA_2S_Z
    POP  DE
    POP  BC
    POP  AF
    RET
; BEZPOŒREDNIE PODPROGRAMY POMOCNICZE STEMPLOWANIA CZASU DLA ASIDE
; Pewny, bezwzglêdny zapis struktur do pamiêci RAM bez u¿ywania rejestru HL
; ==============================================================================

ZAPISZ_STEMPEL_MIN_DIRECT:
    LD   A, (SYS_DZIEN)
    LD   (REJESTR_MIN_RAM), A        ; 1. Dzieñ
    LD   A, (SYS_MIES)
    LD   (REJESTR_MIN_RAM+1), A        ; 2. Miesi¹c
    LD   A, (SYS_GODZ)
    LD   (REJESTR_MIN_RAM+2), A        ; 3. Godzina
    LD   A, (SYS_MIN)
    LD   (REJESTR_MIN_RAM+3), A        ; 4. Minuta
    LD   A, (NR_CZUJNIKA)
    LD   (REJESTR_MIN_RAM+4), A        ; 5. Numer czujnika MIN
    RET

ZAPISZ_STEMPEL_MAX_DIRECT:
    LD   A, (SYS_DZIEN)
    LD   (REJESTR_MIN_RAM+7), A        ; 1. Dzieñ
    LD   A, (SYS_MIES)
    LD   (REJESTR_MIN_RAM+8), A        ; 2. Miesi¹c
    LD   A, (SYS_GODZ)
    LD   (REJESTR_MIN_RAM+9), A        ; 3. Godzina
    LD   A, (SYS_MIN)
    LD   (REJESTR_MIN_RAM+10), A        ; 4. Minuta
    LD   A, (NR_CZUJNIKA)
    LD   (REJESTR_MIN_RAM+11), A        ; 5. Numer czujnika MAX
    RET

;= = = = = = = = =
; to ponizej to ustawianie 9-bit do 12-bit  rozdzielczosci dla czujnika
; i ustawianie alarmu

; ==============================================================================
  ; --- KROK 1: Zapis konfiguracji do RAM pierwszego czujnika ---
;    CALL NMI_OFF
;    CALL OW_WYBIERZ_SENSOR1 
    
;    LD A, 0x4E          ; Rozkaz: Write Scratchpad
;    CALL OW_ZAPISZ_BAJT

;    LD A, 0x4B          ; Bajt 1: TH (75 st. C)
;    CALL OW_ZAPISZ_BAJT

;    LD A, 0x46          ; Bajt 2: TL (70 st. C)
;    CALL OW_ZAPISZ_BAJT

;    LD A, 0x5F          ; Bajt 3: Config Register = 11 bitów (0.125 st. C)
;    CALL OW_ZAPISZ_BAJT   ; 1F 0,50  3F 0.25   7F 0.125  5F 0.0625

    ; --- KROK 2: Zapis do EEPROM pierwszego czujnika ---
;    CALL OW_WYBIERZ_SENSOR1 

;    LD A, 0x48          ; Rozkaz: Copy Scratchpad (zapis do EEPROM)
;    CALL OW_ZAPISZ_BAJT
;    CALL NMI_ON                 ; Przywróæ przerwania

;    CALL Delay_10ms     ; Czas trwania zapisu w EEPROM czujnika

;    RET  

; ------------------------------------------------------------------------------
; ADRESOWANIE KONKRETNEGO CZUJNIKA (Match ROM 0x55)
; ------------------------------------------------------------------------------
;OW_WYBIERZ_SENSOR1:
;    CALL OW_Reset       ; 1. Reset magistrali
    
;    LD A, 0x55          ; 2. Rozkaz Match ROM (wybór konkretnego czujnika)
;    CALL OW_ZAPISZ_BAJT

    ; 3. Wysy³anie 8 bajtów adresu ROM z pamiêci (od 0xFEA0 do 0xFEA7)
;    LD HL, SENSOR1_ROM  ; WskaŸnik HL = 0xFEA0
;    LD B, 8             ; Licznik bajtów
;OW_SendROMLoop:
;    LD A, (HL)          ; Pobierz bajt adresu z pamiêci RAM
;    CALL OW_ZAPISZ_BAJT   ; Wyœlij go po 1-Wire
;    INC HL              ; Nastêpny bajt
;    DJNZ OW_SendROMLoop
;    RET
;          
;Delay_10ms:
;    LD BC, 1538 ; 0602h       ; [10 T] Wartoœæ licznika pêtli
;petla_10ms:
;    DEC BC              ; [6 T]  Zmniejsz BC o 1
;    LD A, B             ; [4 T]  SprawdŸ, czy BC == 0
;    OR C                ; [4 T]
;    JR NZ, petla_10ms       ; [12 T gdy skacze / 7 T przy ostatnim przejœciu] 
;    RET                 ; [10 T] Powrót z procedury

