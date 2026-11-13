#include<iostream>
#include<thread>
#include<mutex>
#include<condition_variable>
#include<atomic>
#include<fstream>
#include<vector>
#include<string>
#include<deque>
#include<unordered_map>
#include<random>
#include<algorithm>

struct FileNameQueue {
  std::vector<std::string> names;
  std::mutex names_mutex;
};

struct ContentQueue {
  std::deque<std::string> content;
  std::mutex content_mutex;
  std::condition_variable not_full;
  std::condition_variable not_empty;
  bool producers_done = false;
};

struct WordCountTable {
  std::unordered_map<std::string,int> counts;
  std::mutex counts_mutex;
};

FileNameQueue file_name_queue;
ContentQueue content_queue;
WordCountTable word_count_table;
std::atomic<int> active_producers;


void producer(){
  std::mt19937 rng(std::random_device{}());
  while(true){
    std::string file_name ;
    {
      std::lock_guard<std::mutex> lg(file_name_queue.names_mutex);
      if(file_name_queue.names.empty()){
        break;
      }
      std::uniform_int_distribution<>distrib(0,static_cast<int>(file_name_queue.names.size())-1);
      int index = distrib(rng);
      file_name = file_name_queue.names[index];
      std::swap(file_name_queue.names[index],file_name_queue.names.back());
      file_name_queue.names.pop_back();
    }

    std::ifstream file(file_name,std::ios::in);
    if(!file.is_open()){
      std::cerr <<"File mentioned in input file not found" << '\n';
      continue ;
    }
    std::string line ;
    while(std::getline(file,line)){
      std::unique_lock<std::mutex> ul(content_queue.content_mutex);
      content_queue.not_full.wait(ul, [] { return content_queue.content.size() < 10; });
      content_queue.content.push_back(line);
      ul.unlock();
      content_queue.not_empty.notify_one();
    }
  }

  if(--active_producers == 0){
    {
      std::lock_guard<std::mutex> lg(content_queue.content_mutex);
      content_queue.producers_done = true;
    }
    content_queue.not_empty.notify_all();
  }

}

void consumer(){
      while(true){
        std::string line ;
        std::unique_lock<std::mutex>ul(content_queue.content_mutex);
        content_queue.not_empty.wait(ul,[]{return !content_queue.content.empty()||content_queue.producers_done;});
        if(content_queue.content.empty() && content_queue.producers_done){
          break ;
        }
        line = content_queue.content.front();
        content_queue.content.pop_front();
        content_queue.not_full.notify_one();
        ul.unlock();

        std::vector<std::string> words ;
        std::string current ;
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

        {
          std::lock_guard<std::mutex> lg(word_count_table.counts_mutex);
          for(const std::string& w : words){
            word_count_table.counts[w]++;
          }
        }
      }

}

int main(int argc , char* argv[]){
    std::ifstream input_file(argv[1], std::ios::in);

    if(!input_file.is_open()){
      std::cerr << "No such input file" << '\n';
      return 1 ;
    }
    std::string file_name ;
    while(std::getline(input_file,file_name)){
      file_name_queue.names.push_back(file_name);
    }
    int num_producers  = std::atoi(argv[2]);
    int num_consumers  = std::atoi(argv[3]);

    active_producers = num_producers;

    std::vector<std::thread> consumer_threads;
    std::vector<std::thread> producer_threads;

    for(int i = 0; i < num_consumers; i++){
      consumer_threads.emplace_back(consumer);
    }
    for(int i = 0; i < num_producers; i++){
      producer_threads.emplace_back(producer);
    }

    for(auto& t : producer_threads){
      t.join();
    }
    for(auto& t : consumer_threads){
      t.join();
    }

    std::vector<std::pair<std::string,int>> sorted_words(word_count_table.counts.begin(), word_count_table.counts.end());
    std::sort(sorted_words.begin(), sorted_words.end());

    for(const auto& p : sorted_words){
      std::cout << p.first << " " << p.second << "\n";
    }

    return 0;
}
