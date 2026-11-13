CXX = g++
CXXFLAGS = -std=c++17 -O3 -Wall
LDFLAGS = -static-libstdc++ -static-libgcc

.PHONY: all problem2 problem3 clean

all: problem2 problem3

problem2: problem2/problem2.cpp
	$(CXX) $(CXXFLAGS) -o problem2/problem2.out problem2/problem2.cpp $(LDFLAGS)

problem3: problem3/230217.cpp
	$(CXX) $(CXXFLAGS) -pthread -o problem3/230217.out problem3/230217.cpp $(LDFLAGS)

clean:
	rm -f problem2/problem2.out problem3/230217.out
