#include <iostream>
#include <fstream>
#include <vector>
#include <regex>
#include <elf.h>
#include <string>

#include "ui.h"

using namespace std;

// memset( 0x0000000000100000 0 4096 -1 )=0x0000000000100000~0xffffffff80027b2d
// !memset( 0xffff800073ccb1a0 0 2432 )=0xffff800073ccb1a0~0xffffffff8009aadb
// memcpy( 0x0000000000102000 0x0000000000100000 4096 -1 )=0x0000000000102000~0xffffffff8007477f
// !memcpy( 0x0000000000102000 0x0000000000100000 4096 )=0x0000000000102000~0xffffffff80027d15
// memmove( 0x0000000001cd2000 0x0000000001caa000 1 -1 )=0x0000000001cd2000~0xffffffff8000f458
// RequestPages( 2 )=0x0000000000100000~0xffffffff80027b03
// FreePage( 0x00000000020bb000 )~0xffffffff8002f654
// !FreePages( 0x0000000001d50000 1001 )~0xffffffff80033201
// malloc( 32 )=0x0000000001319000~0xffffffff80028faa
// free( 0x000000000131d000 )~0xffffffff80029ab3
// new( 32 )=0x0000000001319000~0xffffffff80027f71
// new[]( 14 )=0x000000000131b000~0xffffffff800c23f4
// delete( 0x00000000019ed000 4 )~0xffffffff800ba9fd
// delete[]( 0x000000000131d000 )~0xffffffff800d6851

struct memset_t
{
    uintptr_t dest;
    int val;
    size_t len;
    size_t slen;

    uintptr_t ret;
    uintptr_t caller;
};

struct memcpy_t
{
    uintptr_t dest;
    uintptr_t src;
    size_t len;
    size_t slen;

    uintptr_t ret;
    uintptr_t caller;
};

struct memmove_t
{
    uintptr_t dest;
    uintptr_t src;
    size_t len;
    size_t slen;

    uintptr_t ret;
    uintptr_t caller;
};

struct ReqPages_t
{
    size_t pages;

    uintptr_t ret;
    uintptr_t caller;
};

struct FreePage_t
{
    uintptr_t ptr;

    uintptr_t ret;
    uintptr_t caller;
};

struct FreePages_t
{
    uintptr_t ptr;
    size_t pages;

    uintptr_t ret;
    uintptr_t caller;
};

struct malloc_t
{
    size_t size;

    uintptr_t ret;
    uintptr_t caller;
};

struct free_t
{
    uintptr_t ptr;

    uintptr_t ret;
    uintptr_t caller;
};

struct new_t
{
    size_t size;

    uintptr_t ret;
    uintptr_t caller;
};

struct new_array_t
{
    size_t size;

    uintptr_t ret;
    uintptr_t caller;
};

struct delete_t
{
    uintptr_t ptr;
    size_t size;

    uintptr_t ret;
    uintptr_t caller;
};

struct delete_array_t
{
    uintptr_t ptr;

    uintptr_t ret;
    uintptr_t caller;
};

enum mem_collection_enum_t
{
    memset_e,
    memcpy_e,
    memmove_e,
    ReqPages_e,
    FreePage_e,
    FreePages_e,
    malloc_e,
    free_e,
    new_e,
    new_array_e,
    delete_e,
    delete_array_e
};

struct mem_collection_t
{
    mem_collection_enum_t type;
    memset_t memset;
    memcpy_t memcpy;
    memmove_t memmove;
    ReqPages_t ReqPages;
    FreePage_t FreePage;
    FreePages_t FreePages;
    malloc_t malloc;
    free_t free;
    new_t new_;
    new_array_t new_array;
    delete_t delete_;
    delete_array_t delete_array;
};

namespace SymbolResolver
{
    class Symbols
    {
    private:
        struct SymbolTable
        {
            uintptr_t Address;
            char *FunctionName;
        };

        SymbolTable SymTable[0x10000];
        uintptr_t TotalEntries = 0;

    public:
        Symbols(uintptr_t ImageAddress);
        ~Symbols();
        const char *GetSymbolFromAddress(uintptr_t Address);
        void AddSymbol(uintptr_t Address, const char *Name);
    };
}

namespace SymbolResolver
{
    Symbols::Symbols(uintptr_t ImageAddress)
    {
        printf("Solving symbols for address: %#lx\n", ImageAddress);
        Elf64_Ehdr *Header = (Elf64_Ehdr *)ImageAddress;
        if (Header->e_ident[0] != 0x7F &&
            Header->e_ident[1] != 'E' &&
            Header->e_ident[2] != 'L' &&
            Header->e_ident[3] != 'F')
        {
            printf("Invalid ELF header\n");
            return;
        }
        Elf64_Shdr *ElfSections = (Elf64_Shdr *)(ImageAddress + Header->e_shoff);
        Elf64_Sym *ElfSymbols = nullptr;
        char *strtab = nullptr;

        for (uint16_t i = 0; i < Header->e_shnum; i++)
            switch (ElfSections[i].sh_type)
            {
            case SHT_SYMTAB:
                ElfSymbols = (Elf64_Sym *)(ImageAddress + ElfSections[i].sh_offset);
                this->TotalEntries = ElfSections[i].sh_size / sizeof(Elf64_Sym);
                if (this->TotalEntries >= 0x10000)
                    this->TotalEntries = 0x10000 - 1;

                printf("Symbol table found, %ld entries\n", this->TotalEntries);
                break;
            case SHT_STRTAB:
                if (Header->e_shstrndx == i)
                {
                    printf("String table found, %ld entries\n", ElfSections[i].sh_size);
                }
                else
                {
                    strtab = (char *)(ImageAddress + ElfSections[i].sh_offset);
                    printf("String table found, %ld entries\n", ElfSections[i].sh_size);
                }
                break;
            }

        if (ElfSymbols != nullptr && strtab != nullptr)
        {
            uintptr_t Index, MinimumIndex;
            for (uintptr_t i = 0; i < this->TotalEntries - 1; i++)
            {
                MinimumIndex = i;
                for (Index = i + 1; Index < this->TotalEntries; Index++)
                    if (ElfSymbols[Index].st_value < ElfSymbols[MinimumIndex].st_value)
                        MinimumIndex = Index;
                Elf64_Sym tmp = ElfSymbols[MinimumIndex];
                ElfSymbols[MinimumIndex] = ElfSymbols[i];
                ElfSymbols[i] = tmp;
            }

            while (ElfSymbols[0].st_value == 0)
            {
                ElfSymbols++;
                this->TotalEntries--;
            }

            static int once = 0;
            printf("Symbol table loaded, %ld entries (%ldKB)\n", this->TotalEntries, (this->TotalEntries * sizeof(SymbolTable) / 1024));
            for (uintptr_t i = 0, g = this->TotalEntries; i < g; i++)
            {
                this->SymTable[i].Address = ElfSymbols[i].st_value;
                this->SymTable[i].FunctionName = &strtab[ElfSymbols[i].st_name];
                if (once)
                    printf("Symbol %ld: %#lx %s\n", i, this->SymTable[i].Address, this->SymTable[i].FunctionName);
            }

            if (!once)
                once++;
        }
    }

    Symbols::~Symbols() {}

    const char *Symbols::GetSymbolFromAddress(uintptr_t Address)
    {
        Symbols::SymbolTable Result{0, (char *)"<unknown>"};
        for (uintptr_t i = 0; i < this->TotalEntries; i++)
            if (this->SymTable[i].Address <= Address && this->SymTable[i].Address > Result.Address)
                Result = this->SymTable[i];
        return Result.FunctionName;
    }

    void Symbols::AddSymbol(uintptr_t Address, const char *Name)
    {
        if (this->TotalEntries >= 0x10000)
        {
            printf("Symbol table is full\n");
            return;
        }

        this->SymTable[this->TotalEntries].Address = Address;
        strcpy(this->SymTable[this->TotalEntries].FunctionName, Name);
        this->TotalEntries++;
    }
}

SymbolResolver::Symbols *Symbols = nullptr;

void load_kernel_symbols()
{
    const char *kernel_path = kernel_path_inputbox->value();
    FILE *kernel_file = fopen(kernel_path, "rb");
    if (!kernel_file)
    {
        cout << "Unable to open file" << endl;
        return;
    }

    struct stat kernel_stat_buf;
    int rc = stat(kernel_path, &kernel_stat_buf);
    if (rc != 0)
    {
        cout << "Unable to stat file" << endl;
        return;
    }
    void *kernel_data = malloc(kernel_stat_buf.st_size);
    rc = fread(kernel_data, 1, kernel_stat_buf.st_size, kernel_file);
    if (rc != kernel_stat_buf.st_size)
    {
        cout << "Unable to read file" << endl;
        return;
    }
    fclose(kernel_file);
    Symbols = new SymbolResolver::Symbols((uintptr_t)kernel_data);
}

void main_thread()
{
    /* TODO: This is not complete
        - Detect where is a memory corruption or leak
        - Detect misuses of memset/memcpy/memmove
        - Print on screen the results
     */

    printf("Hello, world!\n");

    regex pattern_memset("memset\\(\\s*(\\S+)\\s+(\\d+)\\s+(\\d+)\\s+(\\S+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_memset_not("memset\\(\\s*(\\S+)\\s+(\\d+)\\s+(\\d+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_memcpy("memcpy\\(\\s*(\\S+)\\s+(\\S+)\\s+(\\d+)\\s+(\\S+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_memcpy_not("memcpy\\(\\s*(\\S+)\\s+(\\S+)\\s+(\\d+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_memmove("memmove\\(\\s*(\\S+)\\s+(\\S+)\\s+(\\d+)\\s+(\\S+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_ReqPages("RequestPages\\(\\s*(\\d+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_FreePage("FreePage\\(\\s*(\\S+)\\s*\\)~(\\S+)");
    regex pattern_FreePages("!FreePages\\(\\s*(\\S+)\\s+(\\d+)\\s*\\)~(\\S+)");
    regex pattern_malloc("malloc\\(\\s*(\\d+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_free("free\\(\\s*(\\S+)\\s*\\)~(\\S+)");
    regex pattern_new("new\\(\\s*(\\d+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_new_array("new\\[\\]\\(\\s*(\\d+)\\s*\\)=(\\S+)~(\\S+)");
    regex pattern_delete("delete\\(\\s*(\\S+)\\s+(\\d+)\\s*\\)~(\\S+)");
    regex pattern_delete_array("delete\\[\\]\\(\\s*(\\S+)\\s*\\)~(\\S+)");

    vector<mem_collection_t> mem_collection_list;

    string line;

    ifstream input_file(file_path_inputbox->value());
    if (!input_file.is_open())
    {
        cout << "Unable to open file" << endl;
        return;
    }

    load_kernel_symbols();

    while (getline(input_file, line))
    {
        smatch match;
        if (regex_search(line, match, pattern_memset) ||
            regex_search(line, match, pattern_memset_not))
        {
            memset_t memset = {
                .dest = strtoull(match[1].str().c_str(), nullptr, 16),
                .val = stoi(match[2].str()),
                .len = stoul(match[3].str()),
                .slen = stoul(match[4].str()),
                .ret = strtoull(match[5].str().c_str(), nullptr, 16),
                .caller = strtoull(match[6].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = memset_e,
                .memset = memset,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_memcpy) ||
                 regex_search(line, match, pattern_memcpy_not))
        {
            memcpy_t memcpy = {
                .dest = strtoull(match[1].str().c_str(), nullptr, 16),
                .src = strtoull(match[2].str().c_str(), nullptr, 16),
                .len = stoul(match[3].str()),
                .slen = stoul(match[4].str()),
                .ret = strtoull(match[5].str().c_str(), nullptr, 16),
                .caller = strtoull(match[6].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = memcpy_e,
                .memcpy = memcpy,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_memmove))
        {
            memmove_t memmove = {
                .dest = strtoull(match[1].str().c_str(), nullptr, 16),
                .src = strtoull(match[2].str().c_str(), nullptr, 16),
                .len = stoul(match[3].str()),
                .slen = stoul(match[4].str()),
                .ret = strtoull(match[5].str().c_str(), nullptr, 16),
                .caller = strtoull(match[6].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = memmove_e,
                .memmove = memmove,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_ReqPages))
        {
            ReqPages_t ReqPages = {
                .pages = stoul(match[1].str()),
                .ret = strtoull(match[2].str().c_str(), nullptr, 16),
                .caller = strtoull(match[3].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = ReqPages_e,
                .ReqPages = ReqPages,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_FreePage))
        {
            FreePage_t FreePage = {
                .ptr = strtoull(match[1].str().c_str(), nullptr, 16),
                .caller = strtoull(match[2].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = FreePage_e,
                .FreePage = FreePage,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_FreePages))
        {
            FreePages_t FreePages = {
                .ptr = strtoull(match[1].str().c_str(), nullptr, 16),
                .pages = stoul(match[2].str()),
                .caller = strtoull(match[3].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = FreePages_e,
                .FreePages = FreePages,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_malloc))
        {
            malloc_t malloc = {
                .size = stoul(match[1].str()),
                .ret = strtoull(match[2].str().c_str(), nullptr, 16),
                .caller = strtoull(match[3].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = malloc_e,
                .malloc = malloc,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_free))
        {
            free_t free = {
                .ptr = strtoull(match[1].str().c_str(), nullptr, 16),
                .caller = strtoull(match[2].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = free_e,
                .free = free,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_new))
        {
            new_t new_ = {
                .size = stoul(match[1].str()),
                .ret = strtoull(match[2].str().c_str(), nullptr, 16),
                .caller = strtoull(match[3].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = new_e,
                .new_ = new_,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_new_array))
        {
            new_array_t new_array = {
                .size = stoul(match[1].str()),
                .ret = strtoull(match[2].str().c_str(), nullptr, 16),
                .caller = strtoull(match[3].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = new_array_e,
                .new_array = new_array,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_delete))
        {
            delete_t delete_ = {
                .ptr = strtoull(match[1].str().c_str(), nullptr, 16),
                .size = stoul(match[2].str()),
                .caller = strtoull(match[3].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = delete_e,
                .delete_ = delete_,
            };
            mem_collection_list.push_back(mem_c);
        }
        else if (regex_search(line, match, pattern_delete_array))
        {
            delete_array_t delete_array = {
                .ptr = strtoull(match[1].str().c_str(), nullptr, 16),
                .caller = strtoull(match[2].str().c_str(), nullptr, 16),
            };
            mem_collection_t mem_c = {
                .type = delete_array_e,
                .delete_array = delete_array,
            };
            mem_collection_list.push_back(mem_c);
        }
    }

    for (const auto &m : mem_collection_list)
    {
        switch (m.type)
        {
        case memset_e:
            printf("memset( %#lx %#x %lu %#lx )=%#lx~%#lx(%s)\n",
                   m.memset.dest, m.memset.val, m.memset.len, m.memset.slen,
                   m.memset.ret, m.memset.caller, Symbols->GetSymbolFromAddress(m.memset.caller));
            break;
        case memcpy_e:
            printf("memcpy( %#lx %#lx %lu %#lx )=%#lx~%#lx(%s)\n",
                   m.memcpy.dest, m.memcpy.src, m.memcpy.len, m.memcpy.slen,
                   m.memcpy.ret, m.memcpy.caller, Symbols->GetSymbolFromAddress(m.memcpy.caller));
            break;
        case memmove_e:
            printf("memmove( %#lx %#lx %lu %#lx )=%#lx~%#lx(%s)\n",
                   m.memmove.dest, m.memmove.src, m.memmove.len, m.memmove.slen,
                   m.memmove.ret, m.memmove.caller, Symbols->GetSymbolFromAddress(m.memmove.caller));
            break;
        case ReqPages_e:
            printf("RequestPages( %lu )=%#lx~%#lx(%s)\n",
                   m.ReqPages.pages, m.ReqPages.ret, m.ReqPages.caller, Symbols->GetSymbolFromAddress(m.ReqPages.caller));
            break;
        case FreePage_e:
            printf("FreePage( %#lx )=%#lx~%#lx(%s)\n",
                   m.FreePage.ptr, m.FreePage.caller, m.FreePage.caller, Symbols->GetSymbolFromAddress(m.FreePage.caller));
            break;
        case FreePages_e:
            printf("FreePages( %#lx %lu )=%#lx~%#lx(%s)\n",
                   m.FreePages.ptr, m.FreePages.pages, m.FreePages.caller, m.FreePages.caller, Symbols->GetSymbolFromAddress(m.FreePages.caller));
            break;
        case malloc_e:
            printf("malloc( %lu )=%#lx~%#lx(%s)\n",
                   m.malloc.size, m.malloc.ret, m.malloc.caller, Symbols->GetSymbolFromAddress(m.malloc.caller));
            break;
        case free_e:
            printf("free( %#lx )=%#lx~%#lx(%s)\n",
                   m.free.ptr, m.free.caller, m.free.caller, Symbols->GetSymbolFromAddress(m.free.caller));
            break;
        case new_e:
            printf("new( %lu )=%#lx~%#lx(%s)\n",
                   m.new_.size, m.new_.ret, m.new_.caller, Symbols->GetSymbolFromAddress(m.new_.caller));
            break;
        case new_array_e:
            printf("new[]( %lu )=%#lx~%#lx(%s)\n",
                   m.new_array.size, m.new_array.ret, m.new_array.caller, Symbols->GetSymbolFromAddress(m.new_array.caller));
            break;
        case delete_e:
            printf("delete( %#lx %lu )=%#lx~%#lx(%s)\n",
                   m.delete_.ptr, m.delete_.size, m.delete_.caller, m.delete_.caller, Symbols->GetSymbolFromAddress(m.delete_.caller));
            break;
        case delete_array_e:
            printf("delete[]( %#lx )=%#lx~%#lx(%s)\n",
                   m.delete_array.ptr, m.delete_array.caller, m.delete_array.caller, Symbols->GetSymbolFromAddress(m.delete_array.caller));
            break;
        default:
            printf("unknown type %d\n", m.type);
            break;
        }
    }
    return;
}

int main()
{
    Fl_Double_Window *w = make_window();
    file_path_inputbox->value("../../memtrk.dmp");
    kernel_path_inputbox->value("../../Kernel/kernel.fsys");
    w->show();

    datatable->rows(10);
    datatable->cols(7);
    datatable->row_header(1);
    // add a row with the data "hello world" without "set"

    pthread_t thread;
    pthread_create(&thread, NULL, (void *(*)(void *))main_thread, NULL);
    return Fl::run();
}
