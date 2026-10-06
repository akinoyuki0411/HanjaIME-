#include <opencv2/objdetect/face.hpp>
#include <opencv2/imgproc.hpp>
#include <iostream>
#include <vector>
#include <cmath>
// A bounded raw BGRA frame protocol. No image files, network, or biometric logging.
int main(int argc, char** argv) {
    if (argc != 3) return 2;
    try {
        cv::setNumThreads(2);
        auto detector = cv::FaceDetectorYN::create(argv[1], "", cv::Size(640,480), 0.9f, 0.3f, 1000);
        auto recognizer = cv::FaceRecognizerSF::create(argv[2], "");
        int w,h;
        while (std::cin >> w >> h) {
            if (std::cin.get() != '\n' || w < 64 || h < 64 || w > 1280 || h > 1280) return 3;
            std::vector<unsigned char> bytes(static_cast<size_t>(w)*h*4);
            if (!std::cin.read(reinterpret_cast<char*>(bytes.data()), bytes.size())) return 4;
            cv::Mat bgr, faces;
            cv::cvtColor(cv::Mat(h,w,CV_8UC4,bytes.data()), bgr, cv::COLOR_BGRA2BGR);
            detector->setInputSize(cv::Size(w,h)); detector->detect(bgr,faces);
            if (faces.rows != 1) {
                std::cout << "{\"error\":\"" << (faces.rows == 0 ? "face_not_found" : "multiple_faces") << "\"}" << std::endl;
                std::fill(bytes.begin(),bytes.end(),0); continue;
            }
            if (faces.at<float>(0,2) < w*0.18f || faces.at<float>(0,3) < h*0.18f) {
                std::cout << "{\"error\":\"face_too_small\"}" << std::endl;
                std::fill(bytes.begin(),bytes.end(),0); continue;
            }
            cv::Mat aligned, feature;
            recognizer->alignCrop(bgr,faces.row(0),aligned); recognizer->feature(aligned,feature);
            if (feature.total()!=128 || !cv::checkRange(feature)) { std::cout << "{\"error\":\"invalid_embedding\"}" << std::endl; continue; }
            feature = feature.reshape(1,1); cv::normalize(feature,feature);
            std::cout << "{\"embedding\":[";
            for (int i=0;i<128;i++) { if(i)std::cout<<',';std::cout<<feature.at<float>(0,i); }
            std::cout << "]}" << std::endl;
            std::fill(bytes.begin(),bytes.end(),0);
        }
    } catch(const cv::Exception&) { return 5; } // Do not echo model paths or frame contents.
}
