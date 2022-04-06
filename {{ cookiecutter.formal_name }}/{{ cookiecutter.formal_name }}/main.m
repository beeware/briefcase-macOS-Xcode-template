//
//  main.m
//  A main module for starting Python projects on macOS.
//
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#include <Python.h>
#include <dlfcn.h>


void crash_dialog(NSString *);
NSString * format_traceback(PyObject *type, PyObject *value, PyObject *traceback);

int main(int argc, char *argv[]) {
    int ret = 0;
    unsigned int i;
    NSString *module_name;
    NSString *python_home;
    NSString *python_path;
    NSString *traceback_str;
    wchar_t *wpython_home;
    wchar_t** python_argv;
    const char* nslog_script;
    PyObject *module;
    PyObject *runpy;
    PyObject *runmodule;
    PyObject *runargs;
    PyObject *result;
    PyObject *exc_type;
    PyObject *exc_value;
    PyObject *exc_traceback;

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

            // Install the nslog script to redirect stdout/stderr if available.
            if (nslog_script == NULL) {
                 NSLog(@"No Python NSLog handler found. stdout/stderr will not be captured.");
                 NSLog(@"To capture stdout/stderr, add 'std-nslog' to your app dependencies.");
             } else {
                 NSLog(@"Installing Python NSLog handler...");
                 FILE *fd = fopen(nslog_script, "r");
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

                // Retrieve the current error state of the interpreter.
                PyErr_Fetch(&exc_type, &exc_value, &exc_traceback);
                PyErr_NormalizeException(&exc_type, &exc_value, &exc_traceback);
                
                if (exc_traceback == NULL) {
                    NSLog(@"Could not retrieve traceback");
                    crash_dialog(@"Could not retrieve traceback");
                    exit(-5);
                }

                traceback_str = format_traceback(exc_type, exc_value, exc_traceback);

                // Restore the error state of the interpreter.
                PyErr_Restore(exc_type, exc_value, exc_traceback);
                
                // Print exception to stderr.
                PyErr_Print();

                // Display stack trace in the crash dialog.
                crash_dialog(traceback_str);
                exit(-6);
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

    // Create a stack trace dialog
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert setMessageText:@"Application has crashed"];
    [alert setInformativeText:@"An unexpected error occurred. Please see the traceback below for more information."];

    // A multiline text widget in a scroll view to contain the stack trace
    NSScrollView *scroll_panel = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    [scroll_panel setHasVerticalScroller:true];
    [scroll_panel setHasHorizontalScroller:false];
    [scroll_panel setAutohidesScrollers:false];
    [scroll_panel setBorderType:NSBezelBorder];

    NSTextView *crash_text = [[NSTextView alloc] init];
    [crash_text setEditable:false];
    [crash_text setSelectable:true];
    [crash_text setString:details];
    [crash_text setVerticallyResizable:true];
    [crash_text setHorizontallyResizable:true];
    [crash_text setFont:[NSFont fontWithName:@"Menlo" size:12.0]];

    [scroll_panel setDocumentView:crash_text];
    [alert setAccessoryView:scroll_panel];

    // Show the crash dialog
    [alert runModal];
}


NSString * format_traceback(PyObject *type, PyObject *value, PyObject *traceback) {
    
    NSRegularExpression *regex;
    NSString *traceback_str;
    PyObject *traceback_list;
    PyObject *traceback_module;
    PyObject *format_exception;
    PyObject *traceback_unicode;
    

    if (traceback == NULL) {
        NSLog(@"Could not retrieve traceback");
        return @"Could not retrieve traceback";
    }

    // Drop the top two stack frames; these are internal
    // wrapper logic, and not in the control of the user.
    for (int i = 0; i < 2; i++) {
        if (PyObject_GetAttrString(traceback, "tb_next") != NULL) {
            traceback = PyObject_GetAttrString(traceback, "tb_next");
        }
    }

    // Format the traceback.
    traceback_module = PyImport_ImportModule("traceback");
    if (traceback_module == NULL) {
        NSLog(@"Could not import traceback");
        return @"Could not import traceback";
    }

    format_exception = PyObject_GetAttrString(traceback_module, "format_exception");
    if (format_exception && PyCallable_Check(format_exception)) {
        traceback_list = PyObject_CallFunctionObjArgs(format_exception, type, value, traceback, NULL);
    } else {
        NSLog(@"Could not find 'format_exception' in 'traceback' module");
        return @"Could not find 'format_exception' in 'traceback' module";
    }
    if (traceback_list == NULL) {
        NSLog(@"Could not format traceback");
        return @"Could not format traceback";
    }

    traceback_unicode = PyUnicode_Join(PyUnicode_FromString(""), traceback_list);
    traceback_str = [NSString stringWithUTF8String:PyUnicode_AsUTF8(PyObject_Str(traceback_unicode))];

    // Take the opportunity to clean up the source path,
    // so paths only refer to the "app local" path.
    regex = [NSRegularExpression regularExpressionWithPattern:@"^  File \"/.*/(.*?).app/Contents/Resources/"
                                                      options:NSRegularExpressionAnchorsMatchLines
                                                        error:nil];
    traceback_str = [regex stringByReplacingMatchesInString:traceback_str
                                                    options:0
                                                      range:NSMakeRange(0, [traceback_str length])
                                               withTemplate:@"  File \"$1.app/Contents/Resources/"];
    return traceback_str;
}
