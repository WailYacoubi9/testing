#!/bin/bash

echo "Generating test data files..."

echo "Generating part1.txt (10000 words)..."
for i in $(seq 1 10000); do echo -n "word$i "; done > part1.txt
echo "" >> part1.txt

echo "Generating part2.txt (15000 words)..."
for i in $(seq 1 15000); do echo -n "word$i "; done > part2.txt
echo "" >> part2.txt

echo "Generating part3.txt (20000 words)..."
for i in $(seq 1 20000); do echo -n "word$i "; done > part3.txt
echo "" >> part3.txt

echo "Generating part4.txt (12000 words)..."
for i in $(seq 1 12000); do echo -n "word$i "; done > part4.txt
echo "" >> part4.txt

echo "Generating part5.txt (18000 words)..."
for i in $(seq 1 18000); do echo -n "word$i "; done > part5.txt
echo "" >> part5.txt

echo "✅ Test data generated!"
echo "Total words: 75000"
