for j in {1..10}; do  
    for i in {1..10000}; do  
        curl -s -o /dev/null -w "%{http_code}\n" http://a1fdf867c75af41b7ba9b63fbe2f864f-334942128.us-east-1.elb.amazonaws.com// &  
    done  
    wait  # Wait for all background curl processes to finish before next iteration
done
