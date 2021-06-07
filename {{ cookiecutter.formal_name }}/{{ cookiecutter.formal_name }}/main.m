//
//  main.m
//  A main module for starting Python projects on macOS.
//
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#include <Python.h>
#include <dlfcn.h>

#ifndef DEBUG
    #define NSLog(...);
#endif

void crash_dialog(NSString *);

int main(int argc, char *argv[]) {
    int ret = 0;
    unsigned int i;
    NSString *module_name;
    NSString *python_home;
    NSString *python_path;
    wchar_t *wpython_home;
    const char* nslog_script;
    wchar_t** python_argv;
    PyObject *module;
    PyObject *runpy;
    PyObject *runmodule;
    PyObject *runargs;
    PyObject *result;
    PyObject *sys;
    PyObject *traceback;

    @autoreleasepool {

        NSString * resourcePath = [[NSBundle mainBundle] resourcePath];

        // Special environment to prefer .pyo; also, don't write bytecode
        // because the process will not have write permissions on the device.
        putenv("PYTHONOPTIMIZE=1");
        putenv("PYTHONDONTWRITEBYTECODE=1");
        putenv("PYTHONUNBUFFERED=1");

        // Set the home for the Python interpreter
        python_home = [NSString stringWithFormat:@"%@/Support/Python/Resources", resourcePath, nil];
        NSLog(@"PythonHome is: %@", python_home);
        wpython_home = Py_DecodeLocale([python_home UTF8String], NULL);
        Py_SetPythonHome(wpython_home);

        // Set the PYTHONPATH
        python_path = [NSString stringWithFormat:@"PYTHONPATH=%@/app:%@/app_packages", resourcePath, resourcePath, nil];
        NSLog(@"PYTHONPATH is: %@", python_path);
        putenv((char *)[python_path UTF8String]);

        NSLog(@"Initializing Python runtime...");
        Py_Initialize();

        // Set the name of the python NSLog bootstrap script
        nslog_script = [
            [[NSBundle mainBundle] pathForResource:@"app_packages/nslog"
                                            ofType:@"py"] cStringUsingEncoding:NSUTF8StringEncoding];

        if (nslog_script == NULL) {
            NSLog(@"Unable to locate NSLog bootstrap script.");
            crash_dialog(@"Unable to locate NSLog bootstrap script.");
            exit(-2);
        }

        // Construct argv for the interpreter
        python_argv = PyMem_RawMalloc(sizeof(wchar_t*) * argc);

        module_name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"MainModule"];
        python_argv[0] = Py_DecodeLocale([module_name UTF8String], NULL);
        for (i = 1; i < argc; i++) {
            python_argv[i] = Py_DecodeLocale(argv[i], NULL);
        }

        PySys_SetArgv(argc, python_argv);

        @try {
            NSLog(@"Installing Python NSLog handler...");
            FILE* fd = fopen(nslog_script, "r");
            if (fd == NULL) {
                NSLog(@"Unable to open nslog.py; abort.");
                crash_dialog(@"Unable to open nslog.py");
                exit(-1);
            }

            ret = PyRun_SimpleFileEx(fd, nslog_script, 1);
            fclose(fd);
            if (ret != 0) {
                NSLog(@"Unable to install Python NSLog handler; abort.");
                crash_dialog(@"Unable to install Python NSLog handler.");
                exit(ret);
            }

            // Start the app module
            NSLog(@"Running app module: %@", module_name);
            runpy = PyImport_ImportModule("runpy");
            if (runpy == NULL) {
                NSLog(@"Could not import runpy module");
                crash_dialog(@"Could not import runpy module");
                exit(-2);
            }

            runmodule = PyObject_GetAttrString(runpy, "_run_module_as_main");
            if (runmodule == NULL) {
                NSLog(@"Could not access runpy._run_module_as_main");
                crash_dialog(@"Could not access runpy._run_module_as_main");
                exit(-3);
            }

            module = PyUnicode_FromWideChar(python_argv[0], wcslen(python_argv[0]));
            if (module == NULL) {
                NSLog(@"Could not convert module name to unicode");
                crash_dialog(@"Could not convert module name to unicode");
                exit(-3);
            }

            runargs = Py_BuildValue("(Oi)", module, 0);
            if (runargs == NULL) {
                NSLog(@"Could not create arguments for runpy._run_module_as_main");
                crash_dialog(@"Could not create arguments for runpy._run_module_as_main");
                exit(-4);
            }

            result = PyObject_Call(runmodule, runargs, NULL);
            if (result == NULL) {
                NSLog(@"Application quit abnormally!");

                // Output the current error state of the interpreter.
                // This will trigger out custom sys.excepthook
                PyErr_Print();

                // Retrieve sys._traceback
                sys = PyImport_ImportModule("sys");
                if (runpy == NULL) {
                    NSLog(@"Could not import sys module");
                    crash_dialog(@"Could not import sys module");
                    exit(-5);
                }

                traceback = PyObject_GetAttrString(sys, "_traceback");
                if (traceback == NULL) {
                    NSLog(@"Could not access sys._traceback");
                    crash_dialog(@"Could not access sys._traceback");
                    exit(-6);
                }
                
                // Display stack trace in the crash dialog.
                crash_dialog([NSString stringWithUTF8String:PyUnicode_AsUTF8(PyObject_Str(traceback))]);
                exit(-7);
            }

        }
        @catch (NSException *exception) {
            NSLog(@"Python runtime error: %@", [exception reason]);
            crash_dialog([NSString stringWithFormat:@"Python runtime error: %@", [exception reason]]);
        }
        @finally {
            Py_Finalize();
        }

        PyMem_RawFree(wpython_home);
        if (python_argv) {
            for (i = 0; i < argc; i++) {
                PyMem_RawFree(python_argv[i]);
            }
            PyMem_RawFree(python_argv);
        }
        NSLog(@"Leaving...");
    }

    exit(ret);
    return ret;
}


void crash_dialog(NSString *details) {
    // We've crashed.
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];

    // The window is 800x600, in the middle of the main screen.
    NSRect screen = NSScreen.mainScreen.visibleFrame;
    NSSize crash_size = NSMakeSize(800, 600);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(
                                                                (screen.size.width - crash_size.width) / 2,
                                                                (screen.size.height - crash_size.height) / 2,
                                                                crash_size.width,
                                                                crash_size.height)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:false];
    [window setTitle:@"Application has crashed!"];

    NSView *layout_view = [[NSView alloc] init];
    [layout_view setTranslatesAutoresizingMaskIntoConstraints:false];
    [window setContentView:layout_view];

    // A text label to introduce the stack trace
    NSTextField *intro_label = [NSTextField labelWithString:@"Details:"];
    [intro_label setTranslatesAutoresizingMaskIntoConstraints:false];
    [layout_view addSubview:intro_label];

    // A multiline text widget in a scroll view to contain the stack trace
    NSScrollView *scroll_panel = [[NSScrollView alloc] init];
    [scroll_panel setHasVerticalScroller:true];
    [scroll_panel setHasHorizontalScroller:false];
    [scroll_panel setAutohidesScrollers:false];
    [scroll_panel setBorderType:NSBezelBorder];
    [scroll_panel setTranslatesAutoresizingMaskIntoConstraints:false];

    NSTextView *crash_text = [[NSTextView alloc] init];
    [crash_text setEditable:false];
    [crash_text setSelectable:true];
    [crash_text setVerticallyResizable:true];
    [crash_text setHorizontallyResizable:false];
    [crash_text setString:details];
    [crash_text setFont:[NSFont fontWithName:@"Menlo" size:12.0]];
    [crash_text setAutoresizingMask:NSViewWidthSizable];

    [scroll_panel setDocumentView:crash_text];
    [layout_view addSubview:scroll_panel];

    // A button to accept the stack trace and close the app.
    // The press action on the button is tied to NSApplication terminate:
    NSButton *accept_button = [NSButton buttonWithTitle:@"OK"
                                                 target:app
                                                 action:@selector(terminate:)];
    [accept_button setBezelStyle:NSRoundedBezelStyle];
    [accept_button setButtonType:NSMomentaryPushInButton];
    [accept_button setTranslatesAutoresizingMaskIntoConstraints:false];

    [layout_view addSubview:accept_button];

    // Layout the window
    // Intro label is attached to the top of the window
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:intro_label
                                                            attribute:NSLayoutAttributeTop
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:layout_view
                                                            attribute:NSLayoutAttributeTop
                                                           multiplier:1.0
                                                             constant:5]];

    // Scroller content expands to fill the window
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:scroll_panel
                                                            attribute:NSLayoutAttributeTop
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:intro_label
                                                            attribute:NSLayoutAttributeBottom
                                                           multiplier:1.0
                                                             constant:5.0]];
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:accept_button
                                                            attribute:NSLayoutAttributeTop
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:scroll_panel
                                                            attribute:NSLayoutAttributeBottom
                                                           multiplier:1.0
                                                             constant:5.0]];

    // Accept button is attached to the bottom of the window
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:layout_view
                                                            attribute:NSLayoutAttributeBottom
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:accept_button
                                                            attribute:NSLayoutAttributeBottom
                                                           multiplier:1.0
                                                             constant:5]];

    // Intro label is the same width as the window
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:intro_label
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:layout_view
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:5]];
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:layout_view
                                                            attribute:NSLayoutAttributeRight
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:intro_label
                                                            attribute:NSLayoutAttributeRight
                                                           multiplier:1.0
                                                             constant:5]];

    // Scroll panel is the same width as the window
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:scroll_panel
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:layout_view
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:5]];
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:layout_view
                                                            attribute:NSLayoutAttributeRight
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:scroll_panel
                                                            attribute:NSLayoutAttributeRight
                                                           multiplier:1.0
                                                             constant:5]];

    // Accept button is the same width as the window.
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:accept_button
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:layout_view
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1.0
                                                             constant:5]];
    [layout_view addConstraint:[NSLayoutConstraint constraintWithItem:layout_view
                                                            attribute:NSLayoutAttributeRight
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:accept_button
                                                            attribute:NSLayoutAttributeRight
                                                           multiplier:1.0
                                                             constant:5]];


    // Show the crash dialog and run the app that will display it.
    [window makeKeyAndOrderFront:nil];
    [app run];
}
