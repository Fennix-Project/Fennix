// FEX is a file format. Right now in development.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void DumpData(const char *Description, unsigned char *Address, unsigned long Length)
{
    printf("-------------------------------------------------------------------------\n");
    unsigned char Buffer[17];
    unsigned long Iterate;

    if (Description != NULL)
        printf("%s:\n", Description);

    for (Iterate = 0; Iterate < Length; Iterate++)
    {
        if ((Iterate % 16) == 0)
        {
            if (Iterate != 0)
                printf("  %s\n", Buffer);
            printf("  %04x ", Iterate);
        }

        printf(" %02x", Address[Iterate]);

        if ((Address[Iterate] < 0x20) || (Address[Iterate] > 0x7e))
            Buffer[Iterate % 16] = '.';
        else
            Buffer[Iterate % 16] = Address[Iterate];

        Buffer[(Iterate % 16) + 1] = '\0';
    }

    while ((Iterate % 16) != 0)
    {
        printf("   ");
        Iterate++;
    }

    printf("  %s\n", Buffer);
    printf("-------------------------------------------------------------------------\n");
}

int main()
{
    FILE *FilePointer;
    char FileName[20];
    unsigned char *Buffer;
    char BufferChar;
    struct stat st;

    printf("--- THIS IS NOT A COMPLETE VERSION ---\n\n");
FileSelection:
    printf("File Name: ");
    fgets(FileName, 20, stdin);
    FileName[strcspn(FileName, "\r\n")] = 0;
    FilePointer = fopen(FileName, "r");

    if (NULL == FilePointer)
    {
        printf("Error opening file %s. Try again...\n", FileName);
        FileName[0] = 0;
        goto FileSelection;
    }

    stat(FileName, &st);
    Buffer = (unsigned char *)malloc(st.st_size);
    fread(Buffer, 1, st.st_size, FilePointer);
    DumpData(FileName, Buffer, st.st_size);

    fclose(FilePointer);
    free(Buffer);
    return 0;
}
