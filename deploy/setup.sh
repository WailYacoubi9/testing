#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   DISTRIBUTED WORD COUNT - Setup Script                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in the right directory
if [ ! -f "Makefile" ] || [ ! -d "src" ]; then
    echo "Error: Please run this script from the project root directory"
    exit 1
fi

# Create bin directory
echo "Creating bin directory..."
mkdir -p bin

# Compile Java files in correct order
echo ""
echo "Compiling Java files..."

echo "  - Compiling config..."
if ! javac -d bin src/config/*.java; then
    echo "Failed to compile config"
    exit 1
fi

echo "  - Compiling cluster management..."
if ! javac -cp bin -d bin src/cluster/*.java; then
    echo "Failed to compile cluster management"
    exit 1
fi

echo "  - Compiling network (workers)..."
if ! javac -cp bin -d bin src/network/worker/*.java; then
    echo "Failed to compile network workers"
    exit 1
fi

echo "  - Compiling network (master)..."
if ! javac -cp bin -d bin src/network/master/*.java; then
    echo "Failed to compile network master"
    exit 1
fi

echo "  - Compiling parser..."
if ! javac -cp bin -d bin src/parser/*.java; then
    echo "Failed to compile parser"
    exit 1
fi

echo "  - Compiling utils..."
if ! javac -cp bin -d bin src/utils/*.java; then
    echo "Failed to compile utils"
    exit 1
fi

echo "  - Compiling scheduler..."
if ! javac -cp bin -d bin src/scheduler/*.java; then
    echo "Failed to compile scheduler"
    exit 1
fi

echo ""
echo "Compiling wordcount program..."
if ! gcc -o wordcount test/wordcount.c; then
    echo "Failed to compile wordcount"
    exit 1
fi

echo ""
echo "Generating test data..."
if ! bash test/generate_data.sh; then
    echo "Failed to generate test data"
    exit 1
fi

echo ""
echo "Setup completed!"
echo ""
echo "Next steps:"
echo "  Local test: java -cp bin scheduler.Main \"[localhost]\""
echo "  Grid5000:"
echo "    1. Reserve nodes: oarsub -I -l nodes=5"
echo "    2. Run: bash deploy/run_distributed.sh"
