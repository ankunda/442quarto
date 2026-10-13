#include <stdio.h>
#include <string.h>

int validate(char *key) {
    int len = strlen(key);
    if (len != 8) return 0;

    if (key[0] != 'K') return 0;

    // Positions 1, 3, 5, 7 must be ASCII digits that sum to 20
    int sum = 0;
    for (int i = 1; i < 8; i += 2) {
        if (key[i] < '0' || key[i] > '9') return 0;
        sum += key[i] - '0';
    }
    if (sum != 20) return 0;

    // Positions 2, 4, 6 must be uppercase letters
    for (int i = 2; i < 8; i += 2) {
        if (key[i] < 'A' || key[i] > 'Z') return 0;
    }

    return 1;
}

int main() {
    char key[64];
    printf("Enter license key: ");
    scanf("%63s", key);

    if (validate(key)) {
        printf("License accepted.\n");
    } else {
        printf("Invalid key.\n");
    }

    return 0;
}
