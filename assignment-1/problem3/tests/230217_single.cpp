#include<iostream>
#include<fstream>
#include<vector>
#include<string>
#include<unordered_map>
#include<algorithm>

int main(int argc, char* argv[]){
    std::ifstream input_file(argv[1], std::ios::in);

    if(!input_file.is_open()){
      std::cerr << "No such input file" << '\n';
      return 1;
    }

    std::vector<std::string> file_names;
    std::string file_name;
    while(std::getline(input_file, file_name)){
      file_names.push_back(file_name);
    }

    std::unordered_map<std::string,int> word_count;

    for(const std::string& fname : file_names){
      std::ifstream file(fname, std::ios::in);
      if(!file.is_open()){
        std::cerr << "File mentioned in input file not found" << '\n';
        continue;
      }

      std::string line;
      while(std::getline(file, line)){
        std::vector<std::string> words;
        std::string current;
        for(char c : line){
          if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')){
            current += c;
          } else {
            if(!current.empty()){
              words.push_back(current);
              current.clear();
            }
          }
        }
        if(!current.empty()){
          words.push_back(current);
        }

        for(const std::string& w : words){
          word_count[w]++;
        }
      }
    }

    std::vector<std::pair<std::string,int>> sorted_words(word_count.begin(), word_count.end());
    std::sort(sorted_words.begin(), sorted_words.end());

    for(const auto& p : sorted_words){
      std::cout << p.first << " " << p.second << "\n";
    }

    return 0;
}
