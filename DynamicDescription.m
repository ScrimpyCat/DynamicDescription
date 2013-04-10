/*
 *  Copyright (c) 2011, Stefan Johnson
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification,
 *  are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice, this list
 *     of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice, this
 *     list of conditions and the following disclaimer in the documentation and/or other
 *     materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>
#import "DynamicDescription.h"

/*
 NOTES:
 Since there's no easy way of guaranteeing that the memory is valid, and if the application happens to be 
 multi-threaded that just makes it considerably more difficult. So for handling what to do with pointers there's
 3 different preprocessor options:
 LOGGING_OBJECT_GUARANTEE_OBJECT_NIL_OR_VALID_MEMORY (Prints the object or class, if invalid memory nil or Nil)
 LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY (Prints what the pointer is pointing to, if invalid memory NULL)
 LOGGING_OBJECT_VERY_UNSAFE_USE_POINTER_OF_UNION (Print what the pointer type in a union is pointing to. In order to use, LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY must be true.)
 
 
 When trying to print the structure's elements it handles it as if all the elements are packed. So depending on the elements
 and whether or not it was set to be packed then it may print incorrect results. If you need the structure to be printed
 then your only option is to make sure it's packed (i.e. __attribute__((packed))).
 
 
 On multi-threaded applications, you should set all the pointer printing preprocessors to 0. Since there's no guarantee
 that the object/pointer would be valid memory. And the values of the instance variables may be off.
 
 Pointers to unions or structures, will just print the pointer. As if it was of type (void *).
 
 Bitfields aren't implemented, so it will print (Incomplete) next to the ivar.
 
 To avoid infinite recursion (and so a crash) if the object contains a reference to itself, or to an object which has a reference to this one and that object's
 description has been changed too. i.e. Anyway that it's possible it could circle back to where it began. You can set LOGGING_OBJECT_PREVENT_INFINITE_RECURSION
 to a value from 0 or higher which sets it to only allow up to LOGGING_OBJECT_PREVENT_INFINITE_RECURSION nested logs.
 */
#define LOGGING_OBJECT_GUARANTEE_OBJECT_NIL_OR_VALID_MEMORY 1
#define LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY 1
#define LOGGING_OBJECT_VERY_UNSAFE_USE_POINTER_OF_UNION 0

#define LOGGING_OBJECT_PREVENT_INFINITE_RECURSION 5


typedef struct TYPE_OF_DATA {
    enum {
        DATA_TYPE_ARRAY,
        DATA_TYPE_STRUCTURE,
        DATA_TYPE_UNION,
        DATA_TYPE_POINTER,
        DATA_TYPE_CHAR,
        DATA_TYPE_INT,
        DATA_TYPE_SHORT,
        DATA_TYPE_LONG,
        DATA_TYPE_LONGLONG,
        DATA_TYPE_UCHAR,
        DATA_TYPE_UINT,
        DATA_TYPE_USHORT,
        DATA_TYPE_ULONG,
        DATA_TYPE_ULONGLONG,
        DATA_TYPE_FLOAT,
        DATA_TYPE_DOUBLE,
        DATA_TYPE_BOOL,
        DATA_TYPE_VOID,
        DATA_TYPE_CHARPTR,
        DATA_TYPE_OBJCOBJECT,
        DATA_TYPE_CLASS,
        DATA_TYPE_SEL
    } type;
    size_t sizeOfType; //Only needed for struct
    id value;
    struct TYPE_OF_DATA *nextType;
} TYPE_OF_DATA;


static void FreeTypeOfData(TYPE_OF_DATA *Data)
{
    for (TYPE_OF_DATA *Type = Data, *Next = NULL; Type; Type = Next)
    {
        if ((Type->type == DATA_TYPE_STRUCTURE) || (Type->type == DATA_TYPE_UNION))
        {
            for (id Pointer in Type->value)
            {
                if ([Pointer isKindOfClass: [NSValue class]])
                {
                    FreeTypeOfData([Pointer pointerValue]);
                }
            }
        }
        
        [Type->value release];
        Next = Type->nextType;
        free(Type);
    }
}

static void ExpandEncoding(const char *Type, NSMutableString *ExpandedType, TYPE_OF_DATA **Data)
{
    const char TypeChar = *Type;
    
    if (TypeChar == _C_ARY_B) //Array
    {
        const char *TypeTemp = Type + 1;
        while (isdigit(*TypeTemp++));
        
        size_t Size = TypeTemp - Type - 1;
        char ArraySize[Size];
        strncpy(ArraySize, Type + 1, --Size);
        ArraySize[Size] = 0;
        
        *Data = malloc(sizeof(TYPE_OF_DATA));
        if (!*Data)
        {
            [ExpandedType appendString: @"(Incomplete)"];
            return; //Incomplete
        }
        
        errno = 0;
        unsigned long Value = strtoul(ArraySize, NULL, 10);
        
        if (errno)
        {
            [ExpandedType appendString: @"(Incomplete)"];
            free(*Data);
            *Data = NULL;
            return; //Incomplete
        }
        
        
        **Data = (TYPE_OF_DATA){ DATA_TYPE_ARRAY, 0, [[NSArray alloc] initWithObjects: [NSNumber numberWithUnsignedLong: Value], [NSString stringWithFormat: @"[%s]", ArraySize], nil], NULL };
        ExpandEncoding(TypeTemp - 1, ExpandedType, &(*Data)->nextType);
        
        (*Data)->sizeOfType = (*Data)->nextType->sizeOfType * Value;
    }
    
    else if ((TypeChar == _C_STRUCT_B) || (TypeChar == _C_UNION_B))
    {
        *Data = malloc(sizeof(TYPE_OF_DATA));
        if (!*Data)
        {
            [ExpandedType appendString: @"(Incomplete)"];
            return; //Incomplete
        }
        
        
        _Bool IsStruct = (TypeChar == _C_STRUCT_B);
        NSMutableArray *NameAndType = [[NSMutableArray alloc] initWithCapacity: 10]; //It would make more sense to use a dictionary but we don't need any of those features
        **Data = (TYPE_OF_DATA){ IsStruct ? DATA_TYPE_STRUCTURE : DATA_TYPE_UNION, 0, NameAndType, NULL };
        
        
        const char *const NameTemp = Type + 1;
        const char *TypeTemp = NameTemp;
        while ((*TypeTemp) && (*TypeTemp++ != '"'));
        
        [NameAndType addObject: [NSString stringWithFormat: @"%.*s", (int)(TypeTemp - (NameTemp + 2)), NameTemp]];
        
        if (*TypeTemp)
        {
            NSArray *TypeData = [[NSString stringWithUTF8String: TypeTemp] componentsSeparatedByString: @"\""];
            size_t TotalSize = 0;
            for (NSUInteger Loop = 0, Count = [TypeData count]; Loop < Count; Loop++)
            {
                [NameAndType addObject: [TypeData objectAtIndex: Loop++]];
                NSString *ElementType = [TypeData objectAtIndex: Loop];
                
                
                const char *ElementTypes = [ElementType UTF8String];
                const char Specifier = ElementTypes[0];
                
                if ((Specifier == _C_STRUCT_B) || (Specifier == _C_UNION_B))
                {
                    const char SpecifierEnd = (Specifier + 1) | 1;
                    //Not the ideal way to go about this, actually is pretty awful.
                    NSMutableString *NewString = [[ElementType mutableCopy] autorelease];
                    for (NSUInteger Loop2 = Loop + 1; Loop2 < Count; Loop2++) [NewString appendFormat: @"\"%s", [[TypeData objectAtIndex: Loop2] UTF8String]];
                    ElementTypes = [NewString UTF8String];
                    size_t Loop2 = 1;
                    for (size_t Occurrence = 1; ElementTypes[Loop2] != '\0'; Loop2++)
                    {
                        if (ElementTypes[Loop2] == Specifier) Occurrence++;
                        else if (ElementTypes[Loop2] == SpecifierEnd)
                        {
                            if (--Occurrence == 0) break;
                        }
                    }
                    
                    char TempElementType[++Loop2 + 1];
                    TempElementType[Loop2] = 0;
                    strncpy(TempElementType, ElementTypes, Loop2);
                    
                    TYPE_OF_DATA *TempData;
                    ExpandEncoding(TempElementType, ExpandedType, &TempData);
                    
                    [NameAndType addObject: [NSValue valueWithPointer: TempData]];
                    TypeData = [[NSString stringWithUTF8String: ElementTypes + Loop2] componentsSeparatedByString: @"\""];
                    Count = [TypeData count];
                    Loop = 0;
                    
                    if (TempData)
                    {
                        if (IsStruct)
                        {
                            TotalSize += TempData->sizeOfType;
                        }
                        
                        else
                        {
                            if (TotalSize < TempData->sizeOfType) TotalSize = TempData->sizeOfType;
                        }
                    }
                }
                
                else
                {
                    TYPE_OF_DATA *TempData;
                    ExpandEncoding(ElementTypes, ExpandedType, &TempData);
                    
                    [NameAndType addObject: [NSValue valueWithPointer: TempData]];
                    
                    if (TempData)
                    {
                        if (IsStruct)
                        {
                            TotalSize += TempData->sizeOfType;
                        }
                        
                        else
                        {
                            if (TotalSize < TempData->sizeOfType) TotalSize = TempData->sizeOfType;
                        }
                    }
                    
                    NSRange Range = [ElementType rangeOfCharacterFromSet: [NSCharacterSet characterSetWithRange: NSMakeRange(_C_ID, _C_ID)]];
                    if ((Range.location != NSNotFound) && (Range.length > 0) && (Loop + 1 < Count))
                    {
                        if (objc_lookUpClass([[TypeData objectAtIndex: Loop + 1] UTF8String])) Loop += 2;
                    }
                }
            }
            
            (*Data)->sizeOfType = TotalSize;
        }
    }
    
    else
    {
        if (TypeChar == _C_PTR) //Pointer
        {
            *Data = malloc(sizeof(TYPE_OF_DATA));
            if (!*Data)
            {
                [ExpandedType appendString: @"(Incomplete)"];
                return; //Incomplete
            }
            
            **Data = (TYPE_OF_DATA){ DATA_TYPE_POINTER, sizeof(void*), nil, NULL };
            ExpandEncoding(((Type[1] == _C_STRUCT_B) || (Type[1] == _C_UNION_B))? &(char){ _C_VOID } : Type + 1, ExpandedType, &(*Data)->nextType);
        }
        
        else //One Type
        {
            *Data = malloc(sizeof(TYPE_OF_DATA));
            if (!*Data)
            {
                [ExpandedType appendString: @"(Incomplete)"];
                return; //Incomplete
            }
            
            **Data = (TYPE_OF_DATA){ DATA_TYPE_ARRAY, 0, nil, NULL };
            
            
            if (TypeChar == _C_CHR)
            {
                (*Data)->type = DATA_TYPE_CHAR;
                (*Data)->sizeOfType = sizeof(char);
            }
            
            else if (TypeChar == _C_INT)
            {
                (*Data)->type = DATA_TYPE_INT;
                (*Data)->sizeOfType = sizeof(int);
            }
            
            else if (TypeChar == _C_SHT)
            {
                (*Data)->type = DATA_TYPE_SHORT;
                (*Data)->sizeOfType = sizeof(short);
            }
            
            else if (TypeChar == _C_LNG)
            {
                (*Data)->type = DATA_TYPE_LONG;
                (*Data)->sizeOfType = sizeof(long);
            }
            
            else if (TypeChar == _C_LNG_LNG)
            {
                (*Data)->type = DATA_TYPE_LONGLONG;
                (*Data)->sizeOfType = sizeof(long long);
            }
            
            else if (TypeChar == _C_UCHR)
            {
                (*Data)->type = DATA_TYPE_UCHAR;
                (*Data)->sizeOfType = sizeof(unsigned char);
            }
            
            else if (TypeChar == _C_UINT)
            {
                (*Data)->type = DATA_TYPE_UINT;
                (*Data)->sizeOfType = sizeof(unsigned int);
            }
            
            else if (TypeChar == _C_USHT)
            {
                (*Data)->type = DATA_TYPE_USHORT;
                (*Data)->sizeOfType = sizeof(unsigned short);
            }
            
            else if (TypeChar == _C_ULNG)
            {
                (*Data)->type = DATA_TYPE_ULONG;
                (*Data)->sizeOfType = sizeof(unsigned long);
            }
            
            else if (TypeChar == _C_ULNG_LNG)
            {
                (*Data)->type = DATA_TYPE_ULONGLONG;
                (*Data)->sizeOfType = sizeof(unsigned long long);
            }
            
            else if (TypeChar == _C_FLT)
            {
                (*Data)->type = DATA_TYPE_FLOAT;
                (*Data)->sizeOfType = sizeof(float);
            }
            
            else if (TypeChar == _C_DBL)
            {
                (*Data)->type = DATA_TYPE_DOUBLE;
                (*Data)->sizeOfType = sizeof(double);
            }
            
            else if (TypeChar == _C_BOOL)
            {
                (*Data)->type = DATA_TYPE_BOOL;
                (*Data)->sizeOfType = sizeof(_Bool);
            }
            
            else if (TypeChar == _C_VOID)
            {
                (*Data)->type = DATA_TYPE_VOID;
                (*Data)->sizeOfType = 0;
            }
            
            else if (TypeChar == _C_CHARPTR)
            {
                (*Data)->type = DATA_TYPE_CHARPTR;
                (*Data)->sizeOfType = sizeof(char*);
            }
            
            else if (TypeChar == _C_ID)
            {
                (*Data)->type = DATA_TYPE_OBJCOBJECT;
                (*Data)->sizeOfType = sizeof(id);
            }
            
            else if (TypeChar == _C_CLASS)
            {
                (*Data)->type = DATA_TYPE_CLASS;
                (*Data)->sizeOfType = sizeof(Class);
            }
            
            else if (TypeChar == _C_SEL)
            {
                (*Data)->type = DATA_TYPE_SEL;
                (*Data)->sizeOfType = sizeof(SEL);
            }
            
            else
            {
                [ExpandedType appendString: @"(Incomplete)"];
                free(*Data);
                *Data = NULL;
                return; //Incomplete
            }
        }
    }
}

void GetIvarValue(TYPE_OF_DATA *Data, NSMutableString *Value, const Ivar Var, id Obj, size_t Index, _Bool IsPtr)
{
    if (!Data) return;
    
    void *Pointer = NULL;
    if (Data->type >= DATA_TYPE_POINTER)
    {
        if (IsPtr)
        {
            Pointer = [Obj pointerValue];
        }
        
        else
        {
            Pointer = (void*)((ptrdiff_t)Obj + (ptrdiff_t)ivar_getOffset(Var));
        }
        
        if (!Pointer) return;
    }
    
    switch (Data->type)
    {
        case DATA_TYPE_ARRAY:;
            NSString *ArraySize = [Data->value objectAtIndex: 1];
            if (ArraySize) [Value appendString: ArraySize];
            
            [Value appendString: @"{ "];
            TYPE_OF_DATA *NextData = Data->nextType;
            size_t Count = [[Data->value objectAtIndex: 0] unsignedLongValue] - 1, Val = 0;
            
            size_t NextTypeSize = 0;
            if (NextData)
            {
                if (NextData->type == DATA_TYPE_ARRAY) Val = 1, NextTypeSize = NextData->sizeOfType;
                else if ((NextData->type == DATA_TYPE_STRUCTURE) || (NextData->type == DATA_TYPE_UNION)) NextTypeSize = NextData->sizeOfType;
            }
            
            id TempObj = Obj;
            for (size_t Loop = 0; Loop < Count; Loop++)
            {
                GetIvarValue(NextData, Value, Var, TempObj, Loop, NO);
                *(ptrdiff_t*)&TempObj += (ptrdiff_t)NextTypeSize;
                [Value appendString: @", "];
            }
            
            GetIvarValue(NextData, Value, Var, TempObj, Count, NO);
            [Value appendString: @" }"];
            break;
            
        case DATA_TYPE_STRUCTURE:;
            NSString *Begin = [NSString stringWithFormat: @"(struct %s){ ", [[Data->value objectAtIndex: 0] UTF8String]], *End = @" }";
            _Bool IsStruct = TRUE;
            
            goto SkipUnion;
        case DATA_TYPE_UNION:
            Begin = [NSString stringWithFormat: @"(union %s)( ", [[Data->value objectAtIndex: 0] UTF8String]], End = @" )";
            IsStruct = FALSE;
            
        SkipUnion:
            [Value appendString: Begin];
            NSMutableArray *NameAndType = Data->value;
            
            NSUInteger Loop = 1;
            for (NSUInteger Count = [NameAndType count] - 3; Loop < Count; Loop++)
            {
                [Value appendFormat: @"%s = ", [[NameAndType objectAtIndex: Loop++] UTF8String]];
                
                TYPE_OF_DATA *Ptr = [[NameAndType objectAtIndex: Loop] pointerValue];
                if (Ptr)
                {
                    #if !LOGGING_OBJECT_VERY_UNSAFE_USE_POINTER_OF_UNION
                    if ((!IsStruct) && ((Ptr->type == DATA_TYPE_POINTER) || (Ptr->type >= DATA_TYPE_CHARPTR)))
                    {
                        [Value appendFormat: @"%p", *(void**)((ptrdiff_t)Obj + (ptrdiff_t)ivar_getOffset(Var))];
                    }
                    
                    else
                    #endif
                    {
                        GetIvarValue(Ptr, Value, Var, Obj, 0, NO);
                        if (IsStruct) *(ptrdiff_t*)&Obj += Ptr->sizeOfType;
                    }
                }
                
                [Value appendString: @", "];
            }
            
            [Value appendFormat: @"%s = ", [[NameAndType objectAtIndex: Loop++] UTF8String]];
            
            TYPE_OF_DATA *Ptr = [[NameAndType objectAtIndex: Loop] pointerValue];
            if (Ptr)
            {
                #if !LOGGING_OBJECT_VERY_UNSAFE_USE_POINTER_OF_UNION
                if ((!IsStruct) && ((Ptr->type == DATA_TYPE_POINTER) || (Ptr->type >= DATA_TYPE_CHARPTR)))
                {
                    [Value appendFormat: @"%p", *(void**)((ptrdiff_t)Obj + (ptrdiff_t)ivar_getOffset(Var))];
                }
                
                else
                #endif
                {
                    GetIvarValue(Ptr, Value, Var, Obj, 0, NO);
                }
            }
            
            [Value appendString: End];
            break;
            
        case DATA_TYPE_POINTER:
            [Value appendFormat: @"%p", ((void**)Pointer)[Index]];
            
            #if LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY
            [Value appendString: @" : "];
            NSValue *NewVal = [NSValue valueWithPointer: ((void**)Pointer)[Index]];
            GetIvarValue(Data->nextType, Value, Var, NewVal, 0, YES);
            #endif
            break;
            /*
             Using NSNumber so it's much easier to handle on different systems/architectures. e.g. long on 32-bit
             is 32-bits so would use the specifier %d, however on 64-bit it is 64-bits so would use %ld.
             */
        case DATA_TYPE_CHAR:
            [Value appendString: [[NSNumber numberWithChar: ((char*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_INT:
            [Value appendString: [[NSNumber numberWithInt: ((int*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_SHORT:
            [Value appendString: [[NSNumber numberWithShort: ((short*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_LONG:
            [Value appendString: [[NSNumber numberWithLong: ((long*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_LONGLONG:
            [Value appendString: [[NSNumber numberWithLongLong: ((long long*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_UCHAR:
            [Value appendString: [[NSNumber numberWithUnsignedChar: ((unsigned char*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_UINT:
            [Value appendString: [[NSNumber numberWithUnsignedInt: ((unsigned int*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_USHORT:
            [Value appendString: [[NSNumber numberWithUnsignedShort: ((unsigned short*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_ULONG:
            [Value appendString: [[NSNumber numberWithUnsignedLong: ((unsigned long*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_ULONGLONG:
            [Value appendString: [[NSNumber numberWithUnsignedLongLong: ((unsigned long long*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_FLOAT:
            [Value appendString: [[NSNumber numberWithFloat: ((float*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_DOUBLE:
            [Value appendString: [[NSNumber numberWithDouble: ((double*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_BOOL:
            [Value appendString: [[NSNumber numberWithBool: ((_Bool*)Pointer)[Index]] stringValue]];
            break;
            
        case DATA_TYPE_VOID:
            break;
            
        case DATA_TYPE_CHARPTR:
            #if LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY
            [Value appendFormat: @"%s", ((char**)Pointer)[Index]];
            #else
            [Value appendFormat: @"%p", ((char**)Pointer)[Index]];
            #endif
            break;
            
        case DATA_TYPE_OBJCOBJECT:
            #if LOGGING_OBJECT_GUARANTEE_OBJECT_NIL_OR_VALID_MEMORY
            [Value appendFormat: @"%@", ((id*)Pointer)[Index]]; //Must be nil if not valid
            #else
            [Value appendFormat: @"%p", ((id*)Pointer)[Index]];
            #endif
            break;
            
        case DATA_TYPE_CLASS:
            #if LOGGING_OBJECT_GUARANTEE_OBJECT_NIL_OR_VALID_MEMORY
            [Value appendFormat: @"%@", ((Class*)Pointer)[Index]]; //Must be Nil if not valid
            #else
            [Value appendFormat: @"%p", ((Class*)Pointer)[Index]];
            #endif
            break;
            
        case DATA_TYPE_SEL:
            #if LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY
            [Value appendString: NSStringFromSelector(((SEL*)Pointer)[Index])];
            #else
            [Value appendFormat: @"%p", (((SEL*)Pointer)[Index])];
            #endif
            break;
    }
}

NSString *LOGDetailedDescription(id self, SEL _cmd)
{
    Class ClassInfo = [self class];
    NSMutableString *String = [NSMutableString stringWithFormat: @"<%s: %p>", class_getName(ClassInfo), self];
    
    static size_t PreventInfiniteLoop = 0;
    if (PreventInfiniteLoop++ > LOGGING_OBJECT_PREVENT_INFINITE_RECURSION) return String;
    
    [String appendString: @"\n{"];
    unsigned int IvarCount;
    Ivar *IvarList = class_copyIvarList(ClassInfo, &IvarCount);
    
    if (IvarList)
    {
        NSAutoreleasePool *Pool = [NSAutoreleasePool new];
        for (unsigned int Loop = 0; Loop < IvarCount; Loop++)
        {
            [String appendFormat: @"\n\t%s", ivar_getName(IvarList[Loop])];
            const char *Type = ivar_getTypeEncoding(IvarList[Loop]);
            
            TYPE_OF_DATA *Data = NULL;
            ExpandEncoding(Type, String, &Data);
            
            [String appendString: @" = "];
            
            NSMutableString *IvarValue = [NSMutableString string];
            GetIvarValue(Data, IvarValue, IvarList[Loop], self, 0, NO);
            [IvarValue replaceOccurrencesOfString: @"\n" withString: @"\n\t" options: NSLiteralSearch range: NSMakeRange(0, [IvarValue length])];
            [String appendString: IvarValue];
            
            FreeTypeOfData(Data);
        }
        free(IvarList);
        [Pool drain];
    }
    
    [String appendString: @"\n}"];
    
    PreventInfiniteLoop--;
    return String;
}
