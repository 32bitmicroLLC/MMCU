# Modules is all you need

What are C++20 Modules?

C++20 introduced modules as a modern alternative to traditional header files and the C preprocessor. Modules enable you to organize code into well-defined, independently compiled components that you import rather than #include. This approach improves compile-time performance, reduces macro leakage and name collisions, and provides clearer control over what parts of a library are exposed to clients.

At a high level:

A module is a collection of C++ code compiled into a reusable binary interface.

You define a module interface with export module …; and consume it with import …;.

Modules replace or augment the traditional pattern of paired .h and .cpp files, helping avoid multiple re-parsing of headers.

Unlike headers, a module’s contents are compiled only once and then reused as needed, which can significantly reduce build times in large code bases.


Here are some useful and reference pages to dive deeper:

Modules (since C++20) — Comprehensive reference on syntax, semantics, and usage from cppreference:
https://en.cppreference.com/w/cpp/language/modules.html

Standard C++ Modules — Clang docs — Practical details on how C++20 modules are supported in Clang:
https://releases.llvm.org/20.1.0/tools/clang/docs/StandardCPlusPlusModules.html

Modules (C++) — Wikipedia’s summary of the feature, history, and how modules integrate with the language:
https://en.wikipedia.org/wiki/Modules_(C%2B%2B)
