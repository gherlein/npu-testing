there are many folders mounted at /external.  Review them with an eye towards
  understanding how to build an app in C++ that uses the NPU.  Specifically, I want a
  command line app that I can pass a jpeg image file to on the command line.  The app
  should do inference on the photo and use the Yolox model to determine how many people
  are in the image.  A person is an image portion that matches the person class to a
  confidence of at least 0.80.  write a thorough design docs/DESIGN.md file.  Use no python.  Just C++
  
  
