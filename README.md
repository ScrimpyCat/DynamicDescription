DynamicDescription
==================

DynamicDescription is a simple Obj-C library that returns a detailed description of an object (its ivars). It can be called manually passing the object and NULL for the selector (it's unused), or it can replace the description method (or any similar method) for a particular class.

It will display all the ivar information (names and current values) that it can for the object specified.

Example
-------

	union something {
	    int a;
	    char b[3];
	};

	struct thesome {
	    int mag[2];
	    char *cool;
	    struct {
			void *interesting;
			int values;
	    } willitwill;
	};

	@interface Blah : NSObject
	{
	    int a[4];
	    NSString *yo;
	    NSString *hmm[2][2][2];
	    NSString **you;
	    NSString ***them[2];
	    void (^own)();
	    
	    union {
			float fVal;
			int iVal;
			NSString *ptrVal;
	    } misc;
	    
	    union something abc;
	    
	    struct {
			int mag;
			void *cool;
	    } unnamed;
	    
	    struct thesome named;
	    
	    
	    struct {
			union {
			    int a;
			    float b;
			} coolu;
			struct {
			    int l;
			    char v;
			    struct {
			        int val;
			        union {
			            char c;
			            short s;
			        } youknow;
			    } field;
			} __attribute__((packed)) very;
	    } funstuff;
	    
	    struct {
			int fun[3][3];
			char seven;
	    } thisisthat;
	    
	    struct {
			float x, y;
	    } positions[3];
	    
	    struct {
			float x, y;
			int fun[3][3];
			char seven;
			struct {
			    int val;
			    union {
			        char c;
			        short s;
			    } youknow;
			} field;
	    } *zzz;
	    
	    int am[3][2][4];
	    
	    id lmo;
	    
	    int v : 3;
	}

	@end

	@interface Foo : NSObject
	{
	    int a, b, c, d;
	    id x;
	}

	@end


	//...
	//Blah initializes to
	yo = @"test?";
	a[0] = 23;
	a[1] = 17;
	a[2] = 0;
	a[3] = 11;
	
	hmm[0][0][0] = @"zero";
	hmm[0][0][1] = @"one";
	hmm[0][1][0] = @"two";
	hmm[0][1][1] = @"three";
	
	hmm[1][0][0] = @"four";
	hmm[1][0][1] = @"five";
	hmm[1][1][0] = @"six";
	hmm[1][1][1] = @"seven";
	
	you = malloc(sizeof(NSString*) * 2);
	you[0] = @"fire";
	you[1] = @"water";
	
	them[0] = malloc(sizeof(NSString**));
	*them[0] = malloc(sizeof(NSString*));
	**them[0] = @"well well well";
	
	own = ^{ puts("soon"); };
	
	misc.ptrVal = @"dd";
	abc.a = 0x00010203;
	
	funstuff.coolu.a = 16;
	funstuff.very.l = 5;
	funstuff.very.v = 12;
	funstuff.very.field.val = 1;
	funstuff.very.field.youknow.s = 77;
	
	
	named.mag[0] = 1;
	named.mag[1] = 2;
	named.cool = "sure is";
	 
	thisisthat.fun[0][0] = 100400;
	thisisthat.fun[0][1] = 4999;
	thisisthat.fun[0][2] = 700382;
	
	thisisthat.fun[1][0] = 1;
	thisisthat.fun[1][1] = 2;
	thisisthat.fun[1][2] = 3;
	
	thisisthat.seven = 4;
	
	
	positions[0].x = 4.3f;
	positions[0].y = 2.0f;
	
	positions[1].x = 0.03f;
	positions[1].y = 0.0f;
	
	positions[2].x = 77.50934f;
	positions[2].y = 123.0f;
	
	am[0][0][0] = 1;
	am[0][0][1] = 2;
	am[0][0][2] = 3;
	am[0][0][3] = 4;
	am[0][1][0] = 5;
	am[0][1][1] = 6;
	am[0][1][2] = 7;
	am[0][1][3] = 8;
	am[1][0][0] = 9;
	am[1][0][1] = 10;
	am[1][0][2] = 11;
	am[1][0][3] = 12;
	am[1][1][0] = 13;
	am[1][1][1] = 14;
	am[1][1][2] = 15;
	am[1][1][3] = 16;
	am[2][0][0] = 17;
	am[2][0][1] = 18;
	am[2][0][2] = 19;
	am[2][0][3] = 20;
	am[2][1][0] = 21;
	am[2][1][1] = 22;
	am[2][1][2] = 23;
	am[2][1][3] = 24;
	
	lmo = [Foo new];

	//...
	//Foo initializes to
	a = 2;
    b = 4;
    c = 6;
  	d = 8;
    x = self;


    //...
    //The printing
    Blah *a = [[Blah new] autorelease];
    NSLog(@"%@", a);
    LOGGING_OBJECT_ADD_DESCRIPTION_FOR_CLASS([Blah class]);
    LOGGING_OBJECT_ADD_DESCRIPTION_FOR_CLASS(NSClassFromString(@"Foo"));
    NSLog(@"%@", a);


If LOGGING_OBJECT_GUARANTEE_OBJECT_NIL_OR_VALID_MEMORY and LOGGING_OBJECT_GUARANTEE_POINTERS_NULL_OR_VALID_MEMORY and LOGGING_OBJECT_VERY_UNSAFE_USE_POINTER_OF_UNION are enabled, and LOGGING_OBJECT_PREVENT_INFINITE_RECURSION is set to 5, the above code will print:

	2013-04-11 05:50:59.848 dyn loging[193:303] <Blah: 0x10010ab90>
	2013-04-11 05:50:59.851 dyn loging[193:303] <Blah: 0x10010ab90>
	{
		a = [4]{ 23, 17, 0, 11 }
		yo = test?
		hmm = [2]{ [2]{ [2]{ zero, one }, [2]{ two, three } }, [2]{ [2]{ four, five }, [2]{ six, seven } } }
		you = 0x100102e50 : fire
		them = [2]{ 0x100102e60 : 0x10010ad50 : well well well, 0x0 :  }
		own = <__NSGlobalBlock__: 0x100007030>
		misc = (union ?)( fVal = 3.892247e-41, iVal = 27776, ptrVal = dd )
		abc = (union something)( a = 66051, b = [3]{ 3, 2, 1 } )
		unnamed = (struct ?){ mag = 0, cool = 0x0 :  }
		named = (struct thesome){ mag = [2]{ 1, 2 }, cool = sure is, willitwill = (struct ?){ interesting = 0x0 : , values = 0 } }
		funstuff = (struct ?){ coolu = (union ?)( a = 16, b = 2.242078e-44 ), very = (struct ?){ l = 5, v = 12, field = (struct ?){ val = 1, youknow = (union ?)( c = 77, s = 77 ) } } }
		thisisthat = (struct ?){ fun = [3]{ [3]{ 100400, 4999, 700382 }, [3]{ 1, 2, 3 }, [3]{ 0, 0, 0 } }, seven = 4 }
		positions = [3]{ (struct ?){ x = 4.3, y = 2 }, (struct ?){ x = 0.03, y = 0 }, (struct ?){ x = 77.50934, y = 123 } }
		zzz = 0x0 : 
		am = [3]{ [2]{ [4]{ 1, 2, 3, 4 }, [4]{ 5, 6, 7, 8 } }, [2]{ [4]{ 9, 10, 11, 12 }, [4]{ 13, 14, 15, 16 } }, [2]{ [4]{ 17, 18, 19, 20 }, [4]{ 21, 22, 23, 24 } } }
		lmo = <Foo: 0x100107fc0>
		{
			a = 2
			b = 4
			c = 6
			d = 8
			x = <Foo: 0x100107fc0>
			{
				a = 2
				b = 4
				c = 6
				d = 8
				x = <Foo: 0x100107fc0>
				{
					a = 2
					b = 4
					c = 6
					d = 8
					x = <Foo: 0x100107fc0>
					{
						a = 2
						b = 4
						c = 6
						d = 8
						x = <Foo: 0x100107fc0>
						{
							a = 2
							b = 4
							c = 6
							d = 8
							x = <Foo: 0x100107fc0>
						}
					}
				}
			}
		}
		v(Incomplete) = 
	}
