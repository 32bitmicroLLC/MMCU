# Hello Main Loop

This chapter introduces the main loop as the main character in the MMCU.

Long time ago when I started learning C as a programming language I was reading the eponymous book the "C Programming Language" well not exactly the original but a translation and a bad one. 

In the original 1978 edition in chapter  "1.1 Getting Started" you come across this interesting code for what we now know as the ["Hello, World!" program](https://en.wikipedia.org/wiki/%22Hello,_World!%22_program). Wikipedia page has a picture of it handwritten
and signed by Brian Kernighan so it must be true. Origins of it are somewhat obscure and
it is not entirely clear what language wast first used to write it was it B or BCPL.
Anyway, it does not really matter for our discussion as we will be looking at the C 
language version in what is now called K&R style aka C78 full glory.

So here it is: 


```c
main()
{
    printf("hello, world\n");
}
```

On the surface it is not much just one function and one call to another function 'printf()'. But looks can be deceiving and there is so much hiding behind this code that it took me couple of years to fully understand machinery that makes this code run properly.

Almost a decade later C got standardized as ISO C aka C89 with some syntax changes and standard libraries. These changes have affected little "hello, world!" program that now looks like this 

```c
#include <stdio.h>
main()
{
    printf("hello, world\n");
}
```

To be honest I like K&R version better the ISO C version but this is just my personal opinion.

All the relevant C standards can be found at [C - Project status and milestones](https://www.open-std.org/jtc1/sc22/wg14/www/projects.html)

Later in my professional life when I started doing embedded development I discovered that "hello, world!" program is so much harder to get running on that little embedded 8-bit micro-controller chip. Sure you can switch to 32-bit MCU with plenty of memory which
I did but it is just multiplying problems you have to overcome to get it running and printing. 

So what is the solution? An LED blinker you might say and yes that is very popular choice
for a first program to run on MCU and we could call it "hello, LED world!".

But I would argue that we need to go even simpler than that. What could be simple then 
a blinker? 

A loop, an infinite loop, a hello main loop! 

It could a 'for' loop:
```c
main()
{
    for(;;);
}
```

or a 'while' loop:
```c
main()
{
    while(1){};
}
```

or even a 'do while' loop:
```c
main()
{
    do{}while(1);
}
```

Choice is yours and for the empty body of the loop it really does not matter.
However, compiler will deal with the difference in how the loop is written 
bottom or top which is entirely different discussion as we will see later.

Well, there is also one more way to create infinite loop but it is using a "forbidden" goto statement. Not recommended unless you are also an assembly programmer.

```c
main()
{
loop: goto loop;
}
```
